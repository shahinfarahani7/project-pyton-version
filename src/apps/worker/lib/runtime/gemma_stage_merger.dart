import 'long_form_section_plan.dart';
import 'worker_pipeline_log.dart';

/// Deterministic join of two long-form stages. Comparison ignores only
/// surrounding whitespace, repeated newlines, and markdown spacing. The
/// emitted text is the original model text with a duplicate prefix removed.
abstract final class GemmaStageMerger {
  /// Suffix/prefix search is limited to this many normalized characters.
  static const overlapWindowChars = 480;

  /// Shorter matches are left in place so ordinary words are not deleted.
  static const minimumOverlapChars = 8;

  /// Continuation context cap. Incomplete fragments and the last one or two
  /// blocks are cut to this length from the end.
  static const continuationTailMaxChars = 400;

  static bool endedIncomplete(String text, {required bool hitOutputLimit}) {
    if (!hitOutputLimit) {
      return false;
    }
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) {
      return false;
    }
    const terminators = {'.', '!', '?', '؟', '。', '…'};
    return !terminators.contains(trimmed[trimmed.length - 1]);
  }

  /// Last incomplete fragment, or the last one or two logical blocks.
  static String continuationTail(
    String soFar, {
    required bool endedIncomplete,
  }) {
    final trimmed = soFar.trimRight();
    if (trimmed.isEmpty) {
      return '';
    }
    if (endedIncomplete) {
      final blocks = _blocks(trimmed);
      final fragment = blocks.isEmpty ? trimmed : blocks.last.text;
      return _capTail(fragment);
    }
    final blocks = _blocks(trimmed);
    if (blocks.isEmpty) {
      return _capTail(trimmed);
    }
    final take = blocks.length >= 2 ? blocks.sublist(blocks.length - 2) : blocks;
    return _capTail(take.map((block) => block.text).join('\n\n'));
  }

  static String continuationPrompt({
    required String original,
    required String tail,
  }) {
    return 'دقیقاً از ادامه متن نیمه‌تمام زیر ادامه بده.\n'
        'هیچ heading، پاراگراف یا آیتم کامل‌شده‌ای را تکرار نکن.\n'
        'اگر آخر متن ناقص است، ابتدا همان جمله یا بخش را کامل کن.\n'
        '\n'
        'درخواست:\n$original\n'
        '\n'
        'ادامهٔ متن:\n$tail';
  }

  static GemmaStageMerge merge({
    required String previousText,
    required String nextText,
    required bool previousEndedIncomplete,
    List<String> completedSectionTitles = const [],
    List<String> plannedSectionTitles = const [],
  }) {
    if (nextText.trim().isEmpty) {
      return GemmaStageMerge(
        text: previousText,
        overlapRemovedChars: 0,
        duplicateBlocksRemoved: 0,
      );
    }

    final withoutRepeatedSections = LongFormSectionPlan.removeDuplicateSections(
      text: nextText,
      plannedSections: plannedSectionTitles,
      completedSections: completedSectionTitles,
      previousText: previousText,
    );
    final stripped = _stripDuplicateLeadingBlocks(
      previousText,
      withoutRepeatedSections.text,
    );
    final stitch = _stitch(
      previous: previousText,
      next: stripped.text,
      previousEndedIncomplete: previousEndedIncomplete,
    );
    WorkerPipelineLog.info(
      WorkerPipelineLog.exec,
      '[STAGE STITCH] previousBoundary=${stitch.previousBoundary} '
      'overlapChars=${stitch.overlapRemovedChars} '
      'overlapWords=${stitch.overlapWords} '
      'partialWordRecovered=${stitch.partialWordRecovered} '
      'duplicatePrefixRemoved=${stitch.duplicatePrefixRemoved}',
    );
    return GemmaStageMerge(
      text: stitch.text,
      overlapRemovedChars: stitch.overlapRemovedChars,
      duplicateBlocksRemoved:
          stripped.removedBlocks + withoutRepeatedSections.removedSections,
      overlapWords: stitch.overlapWords,
      partialWordRecovered: stitch.partialWordRecovered,
      duplicatePrefixRemoved: stitch.duplicatePrefixRemoved,
      previousBoundary: stitch.previousBoundary,
    );
  }

  static GemmaStageMerge _stitch({
    required String previous,
    required String next,
    required bool previousEndedIncomplete,
  }) {
    var left = _stripBoundaryEllipsis(previous, trailing: true);
    var right = _stripBoundaryEllipsis(next, trailing: false);
    final boundary = _boundaryKind(left);
    final charOverlap = _longestOverlapChars(previous: left, next: right);
    var overlapWords = 0;
    var partialWordRecovered = false;
    var duplicatePrefixRemoved = false;
    if (charOverlap > 0) {
      right = right.substring(charOverlap);
      duplicatePrefixRemoved = true;
    } else if (boundary != 'heading' && boundary != 'list_item') {
      final words = _duplicateLeadingWordCount(left, right);
      if (words > 0 && (boundary != 'complete_sentence' || words >= 2)) {
        right = _dropLeadingTokens(right, words);
        overlapWords = words;
        duplicatePrefixRemoved = true;
      } else {
        final glued = _recoverPartialWord(left, right);
        if (glued != null) {
          left = glued.previous;
          right = glued.next;
          partialWordRecovered = true;
        }
      }
    }
    final joined = _join(
      previous: left,
      next: right,
      previousEndedIncomplete: previousEndedIncomplete || partialWordRecovered,
      overlapRemovedChars: charOverlap > 0 || partialWordRecovered ? 1 : 0,
    );
    final text = partialWordRecovered ? '$left$right' : joined;
    return GemmaStageMerge(
      text: text,
      overlapRemovedChars: charOverlap,
      duplicateBlocksRemoved: 0,
      overlapWords: overlapWords,
      partialWordRecovered: partialWordRecovered,
      duplicatePrefixRemoved: duplicatePrefixRemoved,
      previousBoundary: boundary,
    );
  }

  static String _boundaryKind(String previous) {
    final trimmed = previous.trimRight();
    if (trimmed.isEmpty) {
      return 'partial_sentence';
    }
    final lastLine = trimmed.split('\n').last.trim();
    if (_isHeadingLine(lastLine)) {
      return 'heading';
    }
    if (_isListLine(lastLine)) {
      return 'list_item';
    }
    if (LongFormSectionPlan.normalizeHeading(lastLine).isNotEmpty &&
        RegExp(r'[.!?؟。]$').hasMatch(trimmed)) {
      return 'complete_sentence';
    }
    return 'partial_sentence';
  }

  static String _stripBoundaryEllipsis(String text, {required bool trailing}) {
    final pattern = trailing
        ? RegExp(r'(?:[ \t]*\.{3}|[ \t]*…)[ \t]*$')
        : RegExp(r'^(?:[ \t]*\.{3}|[ \t]*…)[ \t]*');
    return text.replaceFirst(pattern, '');
  }

  static int _duplicateLeadingWordCount(String previous, String next) {
    final previousTokens = RegExp(r'\S+').allMatches(previous.trimRight()).map((m) => m.group(0)!).toList();
    final nextTokens = RegExp(r'\S+').allMatches(next.trimLeft()).map((m) => m.group(0)!).toList();
    if (previousTokens.isEmpty || nextTokens.isEmpty) {
      return 0;
    }
    final limit = [
      previousTokens.length,
      nextTokens.length,
      4,
    ].reduce((a, b) => a < b ? a : b);
    for (var count = limit; count >= 1; count--) {
      var same = true;
      for (var index = 0; index < count; index++) {
        final left = LongFormSectionPlan.normalizeHeading(
          previousTokens[previousTokens.length - count + index],
        );
        final right = LongFormSectionPlan.normalizeHeading(nextTokens[index]);
        if (left.length < 2 || left != right) {
          same = false;
          break;
        }
      }
      if (same) {
        return count;
      }
    }
    return 0;
  }

  static String _dropLeadingTokens(String text, int count) {
    var rest = text.trimLeft();
    for (var index = 0; index < count; index++) {
      rest = rest.replaceFirst(RegExp(r'^\S+[ \t]*'), '');
    }
    return rest;
  }

  static _GluedWord? _recoverPartialWord(String previous, String next) {
    final trimmed = previous.trimRight();
    final last = RegExp(r'\S+$').firstMatch(trimmed);
    final first = RegExp(r'^\s*(\S+)').firstMatch(next.trimLeft());
    if (last == null || first == null) {
      return null;
    }
    final fragment = last.group(0)!;
    final continuation = first.group(1)!;
    final foldedFragment = LongFormSectionPlan.normalizeHeading(fragment);
    final foldedContinuation = LongFormSectionPlan.normalizeHeading(continuation);
    if (foldedFragment.length < 2 ||
        foldedContinuation.length <= foldedFragment.length ||
        !foldedContinuation.startsWith(foldedFragment)) {
      return null;
    }
    final cut = trimmed.substring(0, trimmed.length - fragment.length);
    return _GluedWord(cut, next.trimLeft());
  }

  static String _capTail(String text) {
    final trimmed = text.trim();
    if (trimmed.length <= continuationTailMaxChars) {
      return trimmed;
    }
    var window = trimmed.substring(trimmed.length - continuationTailMaxChars);
    final sentenceStart = _lastSentenceStart(window);
    if (sentenceStart > 0) {
      window = window.substring(sentenceStart);
    } else {
      final space = window.indexOf(RegExp(r'\s'));
      if (space > 0 && space < 48) {
        window = window.substring(space + 1);
      }
    }
    return window.trimLeft();
  }

  static int _lastSentenceStart(String window) {
    final matches = RegExp(r'[.!?؟。][ \t]*').allMatches(window);
    if (matches.isEmpty) {
      return -1;
    }
    final last = matches.last;
    if (last.end >= window.length) {
      return -1;
    }
    return last.end;
  }

  static String _join({
    required String previous,
    required String next,
    required bool previousEndedIncomplete,
    required int overlapRemovedChars,
  }) {
    if (next.isEmpty) {
      return previous;
    }
    if (previous.isEmpty) {
      return next;
    }
    if (overlapRemovedChars > 0) {
      return previous + next;
    }
    if (previousEndedIncomplete && !_startsNewBlock(next)) {
      if (_endsWithSpace(previous) || _startsWithSpace(next)) {
        return previous + next;
      }
      return '$previous $next';
    }
    final separator = previous.endsWith('\n\n') ? '' : '\n\n';
    return '$previous$separator${next.trimLeft()}';
  }

  static bool _endsWithSpace(String text) =>
      text.isNotEmpty && _isSpace(text[text.length - 1]);

  static bool _startsWithSpace(String text) => text.isNotEmpty && _isSpace(text[0]);

  static bool _startsNewBlock(String text) {
    final line = text.trimLeft().split('\n').first;
    return _isHeadingLine(line) || _isListLine(line);
  }

  static _Strip _stripDuplicateLeadingBlocks(String previous, String next) {
    final recent = _recentKeys(previous);
    if (recent.isEmpty) {
      return _Strip(text: next.trimLeft(), removedBlocks: 0);
    }
    final blocks = _blocks(next);
    var removed = 0;
    var cursor = 0;
    for (final block in blocks) {
      final key = _fold(block.text).text;
      if (key.isEmpty || !recent.contains(key)) {
        break;
      }
      cursor = block.end;
      removed += 1;
    }
    final rest = cursor == 0 ? next : next.substring(cursor);
    return _Strip(text: rest.trimLeft(), removedBlocks: removed);
  }

  static Set<String> _recentKeys(String previous) {
    final blocks = _blocks(previous);
    if (blocks.isEmpty) {
      return const {};
    }
    final keys = <String>{};
    final start = blocks.length >= 2 ? blocks.length - 2 : 0;
    for (final block in blocks.sublist(start)) {
      final key = _fold(block.text).text;
      if (key.isNotEmpty) {
        keys.add(key);
      }
    }
    for (var index = blocks.length - 1; index >= 0; index--) {
      final line = blocks[index].text.trimLeft().split('\n').first;
      if (_isHeadingLine(line) || _isListLine(line)) {
        final key = _fold(blocks[index].text).text;
        if (key.isNotEmpty) {
          keys.add(key);
        }
        break;
      }
    }
    return keys;
  }

  static int _longestOverlapChars({
    required String previous,
    required String next,
  }) {
    if (previous.isEmpty || next.isEmpty) {
      return 0;
    }
    final foldedPrev = _fold(previous);
    final foldedNext = _fold(next);
    final limit = overlapWindowChars;
    final prevStart = foldedPrev.text.length > limit
        ? foldedPrev.text.length - limit
        : 0;
    final nextLimit = foldedNext.text.length < limit ? foldedNext.text.length : limit;
    final prevSuffix = foldedPrev.text.substring(prevStart);
    var bestFolded = 0;
    final maxK = prevSuffix.length < nextLimit ? prevSuffix.length : nextLimit;
    for (var length = maxK; length >= minimumOverlapChars; length--) {
      if (prevSuffix.endsWith(foldedNext.text.substring(0, length))) {
        bestFolded = length;
        break;
      }
    }
    if (bestFolded == 0) {
      return 0;
    }
    return foldedNext.endExclusive[bestFolded - 1];
  }

  static List<_Block> _blocks(String input) {
    final blocks = <_Block>[];
    final lines = input.split('\n');
    var offset = 0;
    final paragraph = StringBuffer();
    var paragraphStart = 0;
    var inParagraph = false;

    void closeParagraph() {
      if (!inParagraph) {
        return;
      }
      final text = paragraph.toString().trimRight();
      if (text.isNotEmpty) {
        blocks.add(_Block(text, paragraphStart, offset));
      }
      paragraph.clear();
      inParagraph = false;
    }

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final lineEnd = offset + line.length + (index == lines.length - 1 ? 0 : 1);
      if (line.trim().isEmpty) {
        closeParagraph();
        offset = lineEnd;
        continue;
      }
      if (_isHeadingLine(line) || _isListLine(line)) {
        closeParagraph();
        blocks.add(_Block(line.trim(), offset, lineEnd));
        offset = lineEnd;
        continue;
      }
      if (!inParagraph) {
        paragraphStart = offset;
        inParagraph = true;
      } else {
        paragraph.write('\n');
      }
      paragraph.write(line);
      offset = lineEnd;
    }
    closeParagraph();
    return blocks;
  }

  static bool _isHeadingLine(String line) {
    final trimmed = line.trim();
    if (RegExp(r'^#{1,6}\s+\S').hasMatch(trimmed)) {
      return true;
    }
    return RegExp(r'^\*\*.+\*\*:?\s*$').hasMatch(trimmed);
  }

  static bool _isListLine(String line) {
    return RegExp(r'^\s*(?:[-*+]\s+|(?:\d+|[۰-۹]+)[\.\)])\s*\S').hasMatch(line);
  }

  static _Folded _fold(String input) {
    final buffer = StringBuffer();
    final ends = <int>[];
    var index = 0;
    while (index < input.length) {
      if (_isSpace(input[index])) {
        final newline = _whitespaceHasNewline(input, index);
        while (index < input.length && _isSpace(input[index])) {
          index += 1;
        }
        final atEdge = buffer.isEmpty || index >= input.length;
        final beforeBold = input.startsWith('**', index);
        if (atEdge || beforeBold) {
          continue;
        }
        buffer.write(newline ? '\n' : ' ');
        ends.add(index);
        continue;
      }
      if (input.startsWith('**', index)) {
        buffer.write('**');
        index += 2;
        ends
          ..add(index)
          ..add(index);
        while (index < input.length && (input[index] == ' ' || input[index] == '\t')) {
          index += 1;
        }
        continue;
      }
      buffer.write(input[index]);
      index += 1;
      ends.add(index);
    }
    return _Folded(buffer.toString(), ends);
  }

  static bool _isSpace(String char) => char == ' ' || char == '\t' || char == '\n' || char == '\r';

  static bool _whitespaceHasNewline(String input, int index) {
    var cursor = index;
    while (cursor < input.length && _isSpace(input[cursor])) {
      if (input[cursor] == '\n') {
        return true;
      }
      cursor += 1;
    }
    return false;
  }

}

class GemmaStageMerge {
  const GemmaStageMerge({
    required this.text,
    required this.overlapRemovedChars,
    required this.duplicateBlocksRemoved,
    this.overlapWords = 0,
    this.partialWordRecovered = false,
    this.duplicatePrefixRemoved = false,
    this.previousBoundary = '',
  });

  final String text;
  final int overlapRemovedChars;
  final int duplicateBlocksRemoved;
  final int overlapWords;
  final bool partialWordRecovered;
  final bool duplicatePrefixRemoved;
  final String previousBoundary;
}

class _GluedWord {
  const _GluedWord(this.previous, this.next);

  final String previous;
  final String next;
}

class _Strip {
  const _Strip({required this.text, required this.removedBlocks});

  final String text;
  final int removedBlocks;
}

class _Block {
  const _Block(this.text, this.start, this.end);

  final String text;
  final int start;
  final int end;
}

class _Folded {
  const _Folded(this.text, this.endExclusive);

  final String text;
  final List<int> endExclusive;
}
