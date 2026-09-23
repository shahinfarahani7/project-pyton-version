import 'dart:convert';

import '../contracts/worker_error.dart';

/// Structured result from [JsonOutputValidator.extractJsonObject].
class JsonExtractResult {
  const JsonExtractResult({
    required this.rawPreserved,
    this.object,
    this.rejectionStage,
    this.rejectionReason,
    this.literalEscapeRecovered = false,
  });

  final String rawPreserved;
  final Map<String, dynamic>? object;
  final String? rejectionStage;
  final String? rejectionReason;

  /// True when [JsonOutputValidator] decoded via [_tryLiteralEscapeLayerRecovery].
  final bool literalEscapeRecovered;

  bool get ok => object != null;
}

abstract final class JsonOutputValidator {
  static Map<String, dynamic>? parseJsonObject(
    String raw, {
    bool allowSalvage = true,
  }) =>
      extractJsonObject(raw, allowSalvage: allowSalvage).object;

  static JsonExtractResult extractJsonObject(
    String raw, {
    bool allowSalvage = true,
  }) {
    final preserved = raw;
    final thinkStripped = _stripThinkBlocks(raw.trim());
    final cleaned = _stripMarkdownFences(thinkStripped);
    final sources = cleaned == thinkStripped || cleaned.isEmpty
        ? [cleaned]
        : [cleaned, thinkStripped];
    for (final source in sources) {
      if (source.isEmpty) {
        continue;
      }
      final objectCount = _countTopLevelObjects(source);
      if (objectCount != null && objectCount > 1) {
        return JsonExtractResult(
          rawPreserved: preserved,
          rejectionStage: 'boundary',
          rejectionReason: 'json_extract_ambiguous_multiple_objects',
        );
      }
      for (final candidate in _candidates(
        source,
        allowSalvage: allowSalvage,
      )) {
        final decoded = _tryDecodeObject(candidate);
        if (decoded != null) {
          return JsonExtractResult(rawPreserved: preserved, object: decoded);
        }
      }
      final balanced = _extractFirstJsonObject(source);
      if (balanced != null && _tryDecodeObject(balanced) == null) {
        return JsonExtractResult(
          rawPreserved: preserved,
          rejectionStage: 'decode',
          rejectionReason: 'json_extract_decode_failed',
        );
      }
      final recovered = _tryLiteralEscapeLayerRecovery(source);
      if (recovered != null) {
        return JsonExtractResult(
          rawPreserved: preserved,
          object: recovered,
          literalEscapeRecovered: true,
        );
      }
    }
    if (cleaned.isEmpty && thinkStripped.isEmpty) {
      return JsonExtractResult(
        rawPreserved: preserved,
        rejectionStage: 'markdown',
        rejectionReason: 'json_extract_empty_after_strip',
      );
    }
    return JsonExtractResult(
      rawPreserved: preserved,
      rejectionStage: 'boundary',
      rejectionReason: 'json_extract_no_object',
    );
  }

  /// Cuts an oversized but valid object down to the contract limits: duplicate
  /// array items removed, arrays capped, over-long strings cut at a word
  /// boundary. The model has already proved it cannot shorten its own reply on
  /// request, so this runs before any second inference pass.
  static Map<String, dynamic> trimToLimits(
    Map<String, dynamic> data, {
    required int maxArrayItems,
    int maxStringChars = 400,
  }) {
    final trimmed = <String, dynamic>{};
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is List) {
        final seen = <String>{};
        final items = <dynamic>[];
        for (final item in value) {
          final key = item is String ? item.trim().toLowerCase() : '$item';
          if (!seen.add(key)) {
            continue;
          }
          items.add(
            item is String ? _cutAtWord(item, maxStringChars) : item,
          );
          if (items.length >= maxArrayItems) {
            break;
          }
        }
        trimmed[entry.key] = items;
      } else if (value is String) {
        trimmed[entry.key] = _cutAtWord(value, maxStringChars);
      } else {
        trimmed[entry.key] = value;
      }
    }
    return trimmed;
  }

  static String _cutAtWord(String value, int maxChars) {
    if (value.length <= maxChars) {
      return value;
    }
    final head = value.substring(0, maxChars);
    final lastSpace = head.lastIndexOf(' ');
    return lastSpace > maxChars ~/ 2 ? head.substring(0, lastSpace) : head;
  }

  /// Progressively more forgiving readings of the same output: the exact text,
  /// the first balanced object, that object with stray quotes escaped and bare
  /// keys quoted, and finally the same readings cut back to the last valid
  /// member. A small model breaks JSON syntax a different way every run —
  /// unescaped quotes inside a value, an unquoted key copied from the prompt,
  /// a reply cut at the output budget — and a second inference pass repairs
  /// none of them reliably.
  static Iterable<String> _candidates(
    String cleaned, {
    required bool allowSalvage,
  }) sync* {
    final balanced = _extractFirstJsonObject(cleaned);
    final trimmed = allowSalvage ? _cutToLastValidMember(cleaned) : null;
    for (final source in [cleaned, balanced, trimmed]) {
      if (source == null || source.isEmpty) {
        continue;
      }
      yield source;
      final controlEscaped = _escapeControlCharactersInStrings(source);
      yield controlEscaped;
      final quoted = _quoteBareKeys(source);
      yield quoted;
      yield _quoteBareKeys(controlEscaped);
      yield _escapeStrayQuotes(source);
      yield _escapeStrayQuotes(controlEscaped);
      yield _escapeStrayQuotes(quoted);
      yield _escapeStrayQuotes(_quoteBareKeys(controlEscaped));
    }
  }

  static Map<String, dynamic>? _tryDecodeObject(String candidate) {
    if (candidate.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  /// Recovers JSON the model wrote as one escaped string (`\n`, `\"`, … as
  /// literal two-character sequences). Only runs when the normal brace scanner
  /// finds no object, the payload contains those literals, and unescaping
  /// yields exactly one strict [jsonDecode] object with benign trailing junk.
  static Map<String, dynamic>? _tryLiteralEscapeLayerRecovery(String source) {
    if (_extractFirstJsonObject(source) != null) {
      return null;
    }
    if (!source.contains('{') ||
        (!source.contains(r'\n') && !source.contains(r'\"'))) {
      return null;
    }
    final unescaped = _unescapeJsonStringLiterals(source);
    if (unescaped == source) {
      return null;
    }
    final objectCount = _countTopLevelObjects(unescaped);
    if (objectCount != 1) {
      return null;
    }
    final balanced = _extractFirstJsonObject(unescaped);
    if (balanced == null) {
      return null;
    }
    if (!_trailingContentIsBenign(unescaped, balanced)) {
      return null;
    }
    return _tryDecodeObject(balanced);
  }

  /// Decodes JSON string escape sequences written literally in model output.
  /// Unknown `\x` pairs are left unchanged so Windows paths and stray
  /// backslashes are not rewritten globally.
  static String _unescapeJsonStringLiterals(String input) {
    final output = StringBuffer();
    var index = 0;
    while (index < input.length) {
      final char = input[index];
      if (char == r'\' && index + 1 < input.length) {
        final next = input[index + 1];
        switch (next) {
          case 'n':
            output.write('\n');
            index += 2;
            continue;
          case 'r':
            output.write('\r');
            index += 2;
            continue;
          case 't':
            output.write('\t');
            index += 2;
            continue;
          case '"':
            output.write('"');
            index += 2;
            continue;
          case r'\':
            output.write(r'\');
            index += 2;
            continue;
          case '/':
            output.write('/');
            index += 2;
            continue;
          case 'u':
            if (index + 5 < input.length) {
              final hex = input.substring(index + 2, index + 6);
              if (_isHexDigits(hex)) {
                output.writeCharCode(int.parse(hex, radix: 16));
                index += 6;
                continue;
              }
            }
        }
      }
      output.write(char);
      index += 1;
    }
    return output.toString();
  }

  static bool _isHexDigits(String value) {
    if (value.length != 4) {
      return false;
    }
    for (final codeUnit in value.codeUnits) {
      final isDigit = codeUnit >= 48 && codeUnit <= 57;
      final isLower = codeUnit >= 97 && codeUnit <= 102;
      final isUpper = codeUnit >= 65 && codeUnit <= 70;
      if (!isDigit && !isLower && !isUpper) {
        return false;
      }
    }
    return true;
  }

  static bool _trailingContentIsBenign(String unescaped, String balanced) {
    final start = unescaped.indexOf(balanced);
    if (start < 0) {
      return false;
    }
    final after = unescaped.substring(start + balanced.length).trim();
    if (after.isEmpty) {
      return true;
    }
    if (RegExp(r'^`{1,3}$').hasMatch(after)) {
      return true;
    }
    if (after.contains('{')) {
      return false;
    }
    return RegExp(r'^[`\s]*$').hasMatch(after);
  }

  /// Rewrites values the model emitted in the wrong shape — a bare string for
  /// an array field, a one-item array for a string field — before the schema
  /// is checked. The facts are already there, so a task must not fail on the
  /// container type alone.
  static Map<String, dynamic> coerceSchemaTypes(
    Map<String, dynamic> data,
    Map<String, dynamic>? schema,
  ) {
    if (schema == null || schema.isEmpty) {
      return data;
    }
    final coerced = Map<String, dynamic>.of(data);
    for (final entry in schema.entries) {
      if (!coerced.containsKey(entry.key)) {
        continue;
      }
      final value = coerced[entry.key];
      if (value == null) {
        continue;
      }
      final expected = entry.value.toString();
      if (expected.contains('array') && value is! List) {
        coerced[entry.key] = _asList(value);
      } else if (expected.contains('string') && value is! String) {
        coerced[entry.key] = _asString(value);
      } else if (expected.contains('number') && value is! num) {
        final parsed = num.tryParse(value.toString());
        if (parsed != null) {
          coerced[entry.key] = parsed;
        }
      } else if (expected.contains('boolean') && value is! bool) {
        final text = value.toString().toLowerCase();
        if (text == 'true' || text == 'false') {
          coerced[entry.key] = text == 'true';
        }
      }
    }
    return coerced;
  }

  /// Adds the schema fields a cut-off reply never reached, using the empty
  /// value of the declared type. Only meaningful when the caller knows the
  /// generation was stopped, otherwise a real contract break gets hidden.
  static Map<String, dynamic> completeMissingFields(
    Map<String, dynamic> data,
    Map<String, dynamic>? schema,
  ) {
    if (schema == null || schema.isEmpty) {
      return data;
    }
    final completed = Map<String, dynamic>.of(data);
    for (final entry in schema.entries) {
      if (completed.containsKey(entry.key)) {
        continue;
      }
      final expected = entry.value.toString();
      if (expected.contains('array')) {
        completed[entry.key] = const <dynamic>[];
      } else if (expected.contains('string')) {
        completed[entry.key] = '';
      } else if (expected.contains('object')) {
        completed[entry.key] = const <String, dynamic>{};
      }
    }
    return completed;
  }

  static List<dynamic> _asList(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? const [] : [trimmed];
    }
    if (value is Map) {
      return value.values.toList();
    }
    return [value];
  }

  static String _asString(Object? value) {
    if (value is List) {
      return value
          .where((item) => item != null)
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .join('; ');
    }
    return value.toString();
  }

  static WorkerError? validateSchema(
    Map<String, dynamic> data,
    Map<String, dynamic>? schema,
  ) {
    if (schema == null || schema.isEmpty) {
      return null;
    }
    for (final entry in schema.entries) {
      final key = entry.key;
      if (!data.containsKey(key)) {
        return WorkerError(
          code: WorkerErrorCode.outputSchemaMismatch,
          message: 'Required field $key is missing',
          retryable: true,
          stage: WorkerTaskStage.llm,
        );
      }
      final expected = entry.value.toString();
      final value = data[key];
      if (expected.contains('string') && value is! String && value != null) {
        return WorkerError(
          code: WorkerErrorCode.outputSchemaMismatch,
          message: 'Field $key expected string',
          retryable: true,
          stage: WorkerTaskStage.llm,
        );
      }
      if (expected.contains('number') && value is! num && value != null) {
        return WorkerError(
          code: WorkerErrorCode.outputSchemaMismatch,
          message: 'Field $key expected number',
          retryable: true,
          stage: WorkerTaskStage.llm,
        );
      }
      if (expected.contains('boolean') && value is! bool && value != null) {
        return WorkerError(
          code: WorkerErrorCode.outputSchemaMismatch,
          message: 'Field $key expected boolean',
          retryable: true,
          stage: WorkerTaskStage.llm,
        );
      }
      if (expected.contains('array') && value is! List && value != null) {
        return WorkerError(
          code: WorkerErrorCode.outputSchemaMismatch,
          message: 'Field $key expected array',
          retryable: true,
          stage: WorkerTaskStage.llm,
        );
      }
      if (expected.contains('object') && value is! Map && value != null) {
        return WorkerError(
          code: WorkerErrorCode.outputSchemaMismatch,
          message: 'Field $key expected object',
          retryable: true,
          stage: WorkerTaskStage.llm,
        );
      }
    }
    return null;
  }

  static String _stripThinkBlocks(String input) {
    var cleaned = input.replaceAll(
      RegExp(
        r'<\s*think\s*>[\s\S]*?<\s*/\s*think\s*>',
        dotAll: true,
        caseSensitive: false,
      ),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'<think>[\s\S]*?</think>', dotAll: true),
      '',
    );
    return cleaned.trim();
  }

  static String _stripMarkdownFences(String input) {
    final lines = input.split('\n');
    var openIndex = -1;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (line.startsWith('```')) {
        openIndex = index;
        break;
      }
    }
    if (openIndex < 0) {
      return _stripTrailingMalformedFenceLines(input.trim());
    }
    final body = <String>[];
    final openTrimmed = lines[openIndex].trim();
    if (openTrimmed.length > 3) {
      final afterFence = openTrimmed.substring(3).trimLeft();
      if (afterFence.isNotEmpty) {
        body.add(afterFence);
      }
    }
    for (var index = openIndex + 1; index < lines.length; index++) {
      final trimmed = lines[index].trim();
      if (trimmed.startsWith('```') && trimmed.length >= 3) {
        break;
      }
      body.add(lines[index]);
    }
    return _stripTrailingMalformedFenceLines(body.join('\n')).trimRight();
  }

  /// Drops decorative fence fragments the model started but never closed after
  /// `json_complete` (for example a lone `` ` `` line after the closing `}`).
  static String _stripTrailingMalformedFenceLines(String input) {
    final lines = input.split('\n');
    while (lines.isNotEmpty) {
      final last = lines.last.trim();
      if (last.isEmpty) {
        lines.removeLast();
        continue;
      }
      if (RegExp(r'^`{1,3}$').hasMatch(last)) {
        lines.removeLast();
        continue;
      }
      break;
    }
    return lines.join('\n');
  }

  /// Escapes raw control characters small models emit inside JSON string values.
  /// Does not rewrite valid Unicode punctuation such as curly quotes.
  static String _escapeControlCharactersInStrings(String input) {
    final output = StringBuffer();
    var inString = false;
    var escaped = false;
    for (var index = 0; index < input.length; index++) {
      final char = input[index];
      if (!inString) {
        output.write(char);
        if (char == '"') {
          inString = true;
        }
        continue;
      }
      if (escaped) {
        output.write(char);
        escaped = false;
        continue;
      }
      if (char == r'\') {
        output.write(char);
        escaped = true;
        continue;
      }
      if (char == '"') {
        output.write(char);
        inString = false;
        continue;
      }
      switch (char) {
        case '\n':
          output.write(r'\n');
        case '\r':
          output.write(r'\r');
        case '\t':
          output.write(r'\t');
        default:
          output.write(char);
      }
    }
    return output.toString();
  }

  static int? _countTopLevelObjects(String input) {
    var count = 0;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = 0; index < input.length; index++) {
      final char = input[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        if (depth == 0) {
          count += 1;
        }
        depth += 1;
      } else if (char == '}') {
        depth -= 1;
      }
    }
    return depth == 0 ? count : null;
  }

  /// Returns the first balanced `{...}` span, so trailing tokens emitted after
  /// the object closed (prose, a second object, repeated keys) are dropped.
  static String? _extractFirstJsonObject(String input) {
    final start = input.indexOf('{');
    if (start < 0) {
      return null;
    }
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = start; index < input.length; index++) {
      final char = input[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        depth += 1;
      } else if (char == '}') {
        depth -= 1;
        if (depth == 0) {
          return input.substring(start, index + 1);
        }
      }
    }
    return null;
  }

  /// Escapes quotes that sit inside a string value, which the model emits when
  /// it quotes the source text (`"showed "5 minutes away""`). A quote only ends
  /// the string when the next non-space character can follow a value.
  static String _escapeStrayQuotes(String input) {
    final output = StringBuffer();
    var inString = false;
    var escaped = false;
    for (var index = 0; index < input.length; index++) {
      final char = input[index];
      if (!inString) {
        output.write(char);
        if (char == '"') {
          inString = true;
        }
        continue;
      }
      if (escaped) {
        output.write(char);
        escaped = false;
        continue;
      }
      if (char == r'\') {
        output.write(char);
        escaped = true;
        continue;
      }
      if (char != '"') {
        output.write(char);
        continue;
      }
      if (_closesString(input, index)) {
        output.write(char);
        inString = false;
      } else {
        output.write(r'\"');
      }
    }
    return output.toString();
  }

  static bool _closesString(String input, int quoteIndex) {
    for (var index = quoteIndex + 1; index < input.length; index++) {
      final char = input[index];
      if (char == ' ' || char == '\t' || char == '\n' || char == '\r') {
        continue;
      }
      return char == ',' || char == ':' || char == '}' || char == ']';
    }
    return true;
  }

  /// Cuts the object back to its last member that has a quoted key and a
  /// complete value, then closes whatever containers were still open there.
  /// This drops both a member the model never finished writing and trailing
  /// junk it appended after a well-formed one.
  static String? _cutToLastValidMember(String input) {
    final start = input.indexOf('{');
    if (start < 0) {
      return null;
    }
    final frames = <_JsonFrame>[];
    var inString = false;
    var escaped = false;
    var safeEnd = -1;
    var safeClosers = '';

    void markSafe(int end) {
      safeEnd = end;
      safeClosers = frames.reversed
          .map((frame) => frame.isObject ? '}' : ']')
          .join();
    }

    // A member only counts once its key was a proper quoted string, so an
    // unquoted key copied out of the prompt cannot anchor the cut.
    bool valueCompletes() {
      final frame = frames.isEmpty ? null : frames.last;
      if (frame == null) {
        return false;
      }
      return frame.isObject ? frame.expectingValue && frame.keyQuoted : true;
    }

    for (var index = start; index < input.length; index++) {
      final char = input[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"' && _closesString(input, index)) {
          inString = false;
          final frame = frames.isEmpty ? null : frames.last;
          if (frame != null && frame.isObject && !frame.expectingValue) {
            frame.keyQuoted = true;
          } else if (valueCompletes()) {
            markSafe(index + 1);
            frame?.expectingValue = false;
          }
        }
        continue;
      }
      switch (char) {
        case '"':
          inString = true;
        case '{':
        case '[':
          frames.add(
            _JsonFrame(isObject: char == '{', wasValue: valueCompletes()),
          );
        case '}':
        case ']':
          if (frames.isEmpty) {
            return null;
          }
          final closed = frames.removeLast();
          if (frames.isEmpty) {
            // The root object ended; anything after it belongs to another
            // reply and is dropped with the cut.
            index = input.length;
            break;
          }
          if (closed.wasValue) {
            markSafe(index + 1);
          }
          frames.last.expectingValue = false;
        case ':':
          if (frames.isNotEmpty) {
            frames.last.expectingValue = true;
          }
        case ',':
          if (frames.isNotEmpty) {
            frames.last
              ..expectingValue = false
              ..keyQuoted = false;
          }
      }
    }

    if (safeEnd <= start || safeClosers.isEmpty) {
      return null;
    }
    return '${input.substring(start, safeEnd)}$safeClosers';
  }

  /// Quotes keys the model emitted bare, e.g. the `DoNotInventFacts:[]` it
  /// copied out of a prompt rule line. Values and prose are left alone.
  static String _quoteBareKeys(String input) {
    final output = StringBuffer();
    final containers = <bool>[];
    var inString = false;
    var escaped = false;
    var expectKey = false;

    for (var index = 0; index < input.length; index++) {
      final char = input[index];
      if (inString) {
        output.write(char);
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (expectKey && _isBareKeyStart(char)) {
        var end = index;
        while (end < input.length && _isBareKeyPart(input[end])) {
          end += 1;
        }
        var lookahead = end;
        while (lookahead < input.length && _isSpace(input[lookahead])) {
          lookahead += 1;
        }
        if (lookahead < input.length && input[lookahead] == ':') {
          output.write('"${input.substring(index, end)}"');
          index = end - 1;
          expectKey = false;
          continue;
        }
      }
      output.write(char);
      switch (char) {
        case '"':
          inString = true;
          expectKey = false;
        case '{':
          containers.add(true);
          expectKey = true;
        case '[':
          containers.add(false);
          expectKey = false;
        case '}':
        case ']':
          if (containers.isNotEmpty) {
            containers.removeLast();
          }
          expectKey = false;
        case ',':
          expectKey = containers.isNotEmpty && containers.last;
        case ':':
          expectKey = false;
      }
    }
    return output.toString();
  }

  static bool _isSpace(String char) =>
      char == ' ' || char == '\t' || char == '\n' || char == '\r';

  static final _bareKeyStart = RegExp(r'[A-Za-z_$]');
  static final _bareKeyPart = RegExp(r'[A-Za-z0-9_$.\-]');

  static bool _isBareKeyStart(String char) => _bareKeyStart.hasMatch(char);

  static bool _isBareKeyPart(String char) => _bareKeyPart.hasMatch(char);
}

class _JsonFrame {
  _JsonFrame({required this.isObject, required this.wasValue});

  final bool isObject;

  /// Whether this container itself sits in a value position, so closing it
  /// completes a member of the parent.
  final bool wasValue;

  bool expectingValue = false;
  bool keyQuoted = false;
}
