import 'long_form_section_plan.dart';
import 'worker_pipeline_log.dart';

/// Deterministic join of two long-form stages. Comparison ignores only
/// surrounding whitespace, repeated newlines, and markdown spacing. The
/// emitted text is the original model text with a duplicate prefix removed.
abstract final class GemmaStageMerger {
  /// Suffix/prefix search is limited to this many normalized characters.
  static const overlapWindowChars = 480;

  /// Shorter matches are left in place so ordinary words are not deleted.
  /// Partial-word recovery does not use this floor.
  static const minimumOverlapChars = 8;

  /// Whole-word overlaps shorter than this are not treated as a cut token.
  static const minimumPartialWordChars = 3;

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

  static const _overlapStopwords = <String>{
    'و',
    'در',
    'از',
    'با',
    'به',
    'را',
    'که',
    'یا',
    'and',
    'or',
    'of',
    'the',
    'a',
    'an',
    'to',
    'for',
  };

  static GemmaStageMerge _stitch({
    required String previous,
    required String next,
    required bool previousEndedIncomplete,
  }) {
    var left = previous;
    var right = _stripBoundaryEllipsis(next, trailing: false);
    if (previousEndedIncomplete) {
      left = _stripBoundaryEllipsis(left, trailing: true);
      right = _stripPostHeadingEllipsis(right);
    }
    var boundary = _boundaryKind(left);
    final nextIsBlock = _startsNewBlock(right);
    final charOverlap = _longestOverlapChars(previous: left, next: right);
    var overlapWords = 0;
    var partialWordRecovered = false;
    var duplicatePrefixRemoved = false;
    if (charOverlap > 0) {
      right = right.substring(charOverlap);
      duplicatePrefixRemoved = true;
    } else if (boundary != 'heading' && boundary != 'list_item' && !nextIsBlock) {
      final words = _duplicateLeadingWordCount(left, right);
      if (words > 0 && (boundary != 'complete_sentence' || words >= 2)) {
        right = _dropLeadingTokens(right, words);
        overlapWords = words;
        duplicatePrefixRemoved = true;
        boundary = words >= 2 ? 'repeated_phrase' : 'repeated_word';
      } else {
        final glued = _recoverPartialWord(left, right);
        if (glued != null) {
          left = glued.previous;
          right = glued.next;
          partialWordRecovered = true;
          duplicatePrefixRemoved = true;
          boundary = 'partial_word';
        }
      }
    }
    final joined = _join(
      previous: left,
      next: right,
      previousEndedIncomplete: previousEndedIncomplete && !_endsSentence(left),
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
        ? RegExp(r'(?:[ \t]*\.{3}|[ \t]*…)[ \t]*\r?\n?$')
        : RegExp(r'^(?:[ \t]*\.{3}|[ \t]*…)[ \t]*');
    return text.replaceFirst(pattern, '');
  }

  /// Drops a leading ellipsis on the first body line after a heading that
  /// opens the next stage. Ellipsis later in the stage stays.
  static String _stripPostHeadingEllipsis(String next) {
    final lines = next.split('\n');
    var headingIndex = -1;
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].trim().isEmpty) {
        continue;
      }
      if (_startsNewBlock(lines[index])) {
        headingIndex = index;
      }
      break;
    }
    if (headingIndex < 0) {
      return next;
    }
    for (var index = headingIndex + 1; index < lines.length; index++) {
      if (lines[index].trim().isEmpty) {
        continue;
      }
      lines[index] = lines[index].replaceFirst(RegExp(r'^[ \t]*(?:\.{3}|…)[ \t]*'), '');
      break;
    }
    return lines.join('\n');
  }

  static bool _endsSentence(String text) {
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) {
      return false;
    }
    const terminators = {'.', '!', '?', '؟', '。'};
    return terminators.contains(trimmed[trimmed.length - 1]);
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
      if (!same) {
        continue;
      }
      if (count == 1 &&
          _overlapStopwords.contains(
            LongFormSectionPlan.normalizeHeading(previousTokens.last),
          )) {
        continue;
      }
      return count;
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
    if (!_overlapStopwords.contains(foldedFragment) &&
        foldedFragment.length >= minimumPartialWordChars &&
        foldedContinuation.length > foldedFragment.length &&
        foldedContinuation.startsWith(foldedFragment)) {
      final cut = trimmed.substring(0, trimmed.length - fragment.length);
      return _GluedWord(cut, next.trimLeft());
    }
    return _recoverRepeatedSuffix(trimmed, next.trimLeft(), fragment, continuation);
  }

  /// Previous token ends with the next token, as in `پروانه‌پَر` + `پَر)`.
  /// A short grammatical word is not removed unless punctuation or ZWNJ shows
  /// the next token is the repeated tail of a cut word.
  static _GluedWord? _recoverRepeatedSuffix(
    String previous,
    String next,
    String previousToken,
    String nextToken,
  ) {
    final core = nextToken.replaceFirst(
      RegExp(r'''^[()\[\]{}«»"'“”‹›.,:;!?؟،؛…]+|[()\[\]{}«»"'“”‹›.,:;!?؟،؛…]+$'''),
      '',
    );
    if (core.isEmpty ||
        !previousToken.endsWith(core) ||
        previousToken.length <= core.length) {
      return null;
    }
    final folded = LongFormSectionPlan.normalizeHeading(core);
    if (folded.length < 2 || _overlapStopwords.contains(folded)) {
      return null;
    }
    final attachedPunctuation = core != nextToken;
    final compoundBreak = previousToken.contains('\u200c') || previousToken.contains('\u200d');
    if (!attachedPunctuation && !compoundBreak && core.length < minimumPartialWordChars) {
      return null;
    }
    if (!next.startsWith(core)) {
      return null;
    }
    return _GluedWord(previous, next.substring(core.length));
  }

  static String _capTail(String text) {
    final trimmed = text.trim();
    if (trimmed.length <= continuationTailMaxChars) {
      return trimmed;
    }
    final sentence = _unfinishedSentence(trimmed);
    if (sentence.isNotEmpty &&
        sentence.length <= continuationTailMaxChars &&
        sentence.length < trimmed.length) {
      return sentence;
    }
    final paragraph = _lastParagraph(trimmed);
    if (paragraph.isNotEmpty &&
        paragraph.length <= continuationTailMaxChars &&
        paragraph.length < trimmed.length) {
      return paragraph;
    }
    var window = trimmed.substring(trimmed.length - continuationTailMaxChars);
    final space = window.indexOf(RegExp(r'\s'));
    if (space >= 0 && space < 48) {
      window = window.substring(space + 1);
    }
    return window.trimLeft();
  }

  static String _unfinishedSentence(String text) {
    final matches = RegExp(r'[.!?؟。][ \t]*').allMatches(text);
    if (matches.isEmpty) {
      return text;
    }
    final last = matches.last;
    if (last.end >= text.length) {
      return '';
    }
    return text.substring(last.end).trimLeft();
  }

  static String _lastParagraph(String text) {
    final parts = text.split(RegExp(r'\n[ \t]*\n'));
    if (parts.isEmpty) {
      return '';
    }
    return parts.last.trim();
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
      if (_endsWithSpace(previous) || _startsWithSpace(next) || _joinsWithoutSpace(previous, next)) {
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

  static bool _joinsWithoutSpace(String previous, String next) {
    if (previous.isEmpty || next.isEmpty) {
      return false;
    }
    const openers = {'«', '“', '(', '[', '‹', '{'};
    const closers = {'»', '”', ')', ']', '›', '}', '،', ',', ':', '؛', '.', '!', '?', '؟'};
    return openers.contains(previous[previous.length - 1]) || closers.contains(next[0]);
  }

  static bool _startsNewBlock(String text) {
    final line = text.trimLeft().split('\n').first.trim();
    return _isHeadingLine(line) || _isListLine(line) || _isColonHeading(line);
  }

  static bool _isColonHeading(String line) {
    final trimmed = line.trim();
    if (!trimmed.endsWith(':') && !trimmed.endsWith('：')) {
      return false;
    }
    final tokens = trimmed.split(RegExp(r'\s+')).where((token) => token.isNotEmpty).length;
    return tokens > 0 && tokens <= 8;
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
