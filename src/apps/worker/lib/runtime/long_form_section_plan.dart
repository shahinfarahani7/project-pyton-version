import 'worker_pipeline_log.dart';

/// Deterministic outline for a long-form document. No model call.
///
/// The titles are a generic article shape. They are not tied to one subject.
class LongFormSectionPlan {
  static const marker = '<EDGEMINT_DONE>';

  static const englishSections = <String>[
    'Introduction',
    'Definition and scope',
    'Structure',
    'Process',
    'Mechanisms',
    'Context',
    'Effects',
    'Implications',
    'Variations',
    'Open questions',
    'Conclusion',
  ];

  static const persianSections = <String>[
    'مقدمه',
    'تعریف و دامنه',
    'ساختار',
    'فرایند',
    'سازوکار',
    'زمینه و محیط',
    'اثرها و رابطه‌ها',
    'پیامدهای عملی',
    'تنوع‌ها',
    'پرسش‌های باز',
    'جمع‌بندی',
  ];

  static List<String> sectionsFor(String prompt) {
    final persian = RegExp(r'[\u0600-\u06FF]').hasMatch(prompt);
    return persian ? persianSections : englishSections;
  }

  static bool containsMarker(String text) => text.contains(marker);

  static String stripMarker(String text) {
    return text.replaceAll(marker, '').trimRight();
  }

  /// Shared identity for a planned title and a generated heading.
  static String normalizeHeading(String raw) {
    var text = raw.trim().toLowerCase();
    text = text.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u200c\u200d\u00ad]'), '');
    text = text.replaceAll('ي', 'ی').replaceAll('ك', 'ک').replaceAll('ة', 'ه');
    text = text.replaceAll('\u00a0', ' ');
    const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    for (var index = 0; index < 10; index++) {
      text = text
          .replaceAll(persianDigits[index], '$index')
          .replaceAll(arabicDigits[index], '$index');
    }
    text = text.replaceFirst(RegExp(r'^(?:#{1,6}[ \t]*)+'), '');
    text = text.replaceFirst(RegExp(r'^[-*+][ \t]+'), '');
    text = text.replaceAll(RegExp(r'[*_`]+'), '');
    text = text.replaceFirst(RegExp(r'^[0-9]+[.)][ \t]*'), '');
    text = text.replaceAll(
      RegExp(r'''[.,:;!?؟،؛。…:："'"“”«»()\[\]{}<>|\\/+\-–—]+'''),
      ' ',
    );
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }

  static bool isStructuralHeading(List<String> lines, int index) {
    if (index < 0 || index >= lines.length) {
      return false;
    }
    final raw = lines[index].trim();
    if (raw.isEmpty) {
      return false;
    }
    final kind = _headingKind(raw);
    if (kind == _HeadingKind.none) {
      return false;
    }
    final tokens = normalizeHeading(raw)
        .split(' ')
        .where((token) => token.isNotEmpty)
        .length;
    if (tokens == 0) {
      return false;
    }
    if (kind == _HeadingKind.markdown || kind == _HeadingKind.bold) {
      return tokens <= SectionMatchThresholds.maxMarkedHeadingTokens;
    }
    if (_endsSentence(raw) || tokens > SectionMatchThresholds.maxPlainHeadingTokens) {
      return false;
    }
    if (kind == _HeadingKind.plain && _readsAsProse(raw)) {
      return false;
    }
    if (kind == _HeadingKind.plain && !_hasFollowingParagraph(lines, index)) {
      return false;
    }
    return true;
  }

  static bool _readsAsProse(String raw) {
    final tokens = normalizeHeading(raw).split(' ').where((token) => token.isNotEmpty);
    for (final token in tokens) {
      if (_proseMarkers.contains(token) || token.startsWith('می') || token.startsWith('نمی')) {
        return true;
      }
    }
    return false;
  }

  static _HeadingKind _headingKind(String raw) {
    if (RegExp(r'^#{1,6}[ \t]+\S').hasMatch(raw)) {
      return _HeadingKind.markdown;
    }
    if (RegExp(r'^\*\*[^*\n].+\*\*:?[ \t]*$').hasMatch(raw) ||
        RegExp(r'^_[^_\n].+_:?[ \t]*$').hasMatch(raw) ||
        RegExp(r'^\*[^*\n].+\*:?[ \t]*$').hasMatch(raw)) {
      return _HeadingKind.bold;
    }
    if (RegExp(r'^(?:[0-9]+|[۰-۹]+)[.)][ \t]+\S').hasMatch(raw)) {
      return _HeadingKind.numbered;
    }
    return _HeadingKind.plain;
  }

  static bool _endsSentence(String raw) {
    final trimmed = raw.trimRight();
    if (trimmed.isEmpty) {
      return false;
    }
    const terminators = {'.', '!', '?', '؟', '。'};
    return terminators.contains(trimmed[trimmed.length - 1]);
  }

  static bool _hasFollowingParagraph(List<String> lines, int index) {
    var cursor = index + 1;
    if (cursor >= lines.length) {
      return false;
    }
    if (lines[cursor].trim().isEmpty) {
      cursor += 1;
      if (cursor >= lines.length) {
        return false;
      }
    }
    return lines[cursor].trim().isNotEmpty;
  }

  static LongFormSectionCleanup removeDuplicateSections({
    required String text,
    required List<String> plannedSections,
    required List<String> completedSections,
    String previousText = '',
  }) {
    if (plannedSections.isEmpty) {
      return LongFormSectionCleanup(text, 0);
    }
    final currentIndex = completedSections.length > plannedSections.length
        ? plannedSections.length
        : completedSections.length;
    final previousLines = previousText.split('\n');
    final alreadyPresent = <int>{};
    for (var index = 0; index < previousLines.length; index++) {
      if (!isStructuralHeading(previousLines, index)) {
        continue;
      }
      final match = LongFormSectionMatcher.match(
        generatedHeading: previousLines[index],
        plannedSections: plannedSections,
        fromIndex: 0,
      );
      if (match.isMatch) {
        alreadyPresent.add(match.matchedSectionIndex);
      }
    }
    final lines = text.split('\n');
    final kept = <String>[];
    final seen = <int>{};
    var skipping = false;
    var removed = 0;
    for (var index = 0; index < lines.length; index++) {
      if (!isStructuralHeading(lines, index)) {
        if (!skipping) {
          kept.add(lines[index]);
        }
        continue;
      }
      final match = LongFormSectionMatcher.match(
        generatedHeading: lines[index],
        plannedSections: plannedSections,
        fromIndex: 0,
      );
      if (!match.isMatch) {
        if (!skipping) {
          kept.add(lines[index]);
        }
        continue;
      }
      final sectionIndex = match.matchedSectionIndex;
      final completed = sectionIndex < currentIndex;
      if (completed || seen.contains(sectionIndex)) {
        skipping = true;
        removed += 1;
        continue;
      }
      if (alreadyPresent.contains(sectionIndex)) {
        seen.add(sectionIndex);
        removed += 1;
        skipping = false;
        continue;
      }
      seen.add(sectionIndex);
      skipping = false;
      kept.add(lines[index]);
    }
    final joined = kept.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trimRight();
    return LongFormSectionCleanup(joined, removed);
  }
}

class LongFormSectionCleanup {
  const LongFormSectionCleanup(this.text, this.removedSections);

  final String text;
  final int removedSections;
}

class LongFormSectionProgress {
  LongFormSectionProgress(this.plannedSections);

  final List<String> plannedSections;
  int currentIndex = 0;

  List<String> get completedSections =>
      plannedSections.take(currentIndex).toList(growable: false);

  String? get currentSection =>
      currentIndex < plannedSections.length ? plannedSections[currentIndex] : null;

  List<String> get remainingSections => currentIndex + 1 >= plannedSections.length
      ? const []
      : plannedSections.sublist(currentIndex + 1);

  bool get plannedSectionsComplete =>
      plannedSections.isNotEmpty && currentIndex >= plannedSections.length;

  /// Moves the cursor to the furthest real heading that maps forward.
  /// The cursor never moves backward.
  void observe(String stageText) {
    if (plannedSectionsComplete || plannedSections.isEmpty) {
      return;
    }
    final lines = stageText.split('\n');
    final startIndex = currentIndex;
    var furthest = currentIndex;
    for (var index = 0; index < lines.length; index++) {
      if (!LongFormSectionPlan.isStructuralHeading(lines, index)) {
        continue;
      }
      final match = LongFormSectionMatcher.match(
        generatedHeading: lines[index],
        plannedSections: plannedSections,
        fromIndex: startIndex,
      );
      final moves = match.isMatch && match.matchedSectionIndex > startIndex;
      if (match.isMatch && match.matchedSectionIndex > furthest) {
        furthest = match.matchedSectionIndex;
      }
      WorkerPipelineLog.info(
        WorkerPipelineLog.exec,
        '[SECTION MATCH] generatedHeading="${lines[index].trim()}" '
        'normalizedHeading="${match.normalizedHeading}" '
        'matchedSectionIndex=${match.isMatch ? match.matchedSectionIndex : -1} '
        'matchedCanonicalTitle="${match.matchedCanonicalTitle}" '
        'score=${match.score.toStringAsFixed(2)} '
        'matchType=${match.matchType} '
        'advanced=$moves '
        'reason=${moves ? 'forward_match' : (match.isMatch ? 'already_current' : 'no_forward_match')}',
      );
    }
    currentIndex = furthest;
    WorkerPipelineLog.info(
      WorkerPipelineLog.exec,
      '[SECTION STATE] completed=[${completedSections.join(', ')}] '
      'current=${currentSection ?? '(none)'} '
      'remaining=[${remainingSections.join(', ')}]',
    );
  }

  String promptBlock() {
    final completed = completedSections.isEmpty
        ? '- (none)'
        : completedSections.map((section) => '- $section').join('\n');
    final current = currentSection ?? '(none)';
    final remaining = remainingSections.isEmpty
        ? '- (none)'
        : remainingSections.map((section) => '- $section').join('\n');
    return 'Completed sections:\n$completed\n'
        '\n'
        'Current section:\n- $current\n'
        '\n'
        'Remaining sections:\n$remaining\n'
        '\n'
        'Continue only from the current unfinished point.\n'
        'Do not repeat completed sections.\n';
  }
}

enum _HeadingKind { none, markdown, bold, numbered, plain }

const _proseMarkers = <String>{
  'است',
  'هست',
  'هستند',
  'بود',
  'شد',
  'کرد',
  'دارد',
  'دارند',
  'خواهد',
  'is',
  'are',
  'was',
  'were',
  'has',
  'have',
  'will',
};

/// Central scores for plan-driven heading matching. No topic list.
abstract final class SectionMatchThresholds {
  static const minimumScore = 0.72;
  static const exact = 1.0;
  static const prefix = 0.92;
  static const morphologicalPrefix = 0.86;
  static const containment = 0.84;
  static const tokenOverlap = 0.78;
  static const lexical = 0.72;
  static const minimumTokenOverlapRatio = 0.6;
  static const minimumLexicalCoverage = 0.8;
  static const minimumTitleChars = 3;
  static const minimumLexicalTitleChars = 5;
  static const maxPlainHeadingTokens = 6;
  static const maxMarkedHeadingTokens = 12;
}

class SectionMatch {
  const SectionMatch({
    required this.normalizedHeading,
    required this.matchedSectionIndex,
    required this.matchedCanonicalTitle,
    required this.score,
    required this.matchType,
  });

  const SectionMatch.none(this.normalizedHeading)
    : matchedSectionIndex = -1,
      matchedCanonicalTitle = '',
      score = 0,
      matchType = 'none';

  final String normalizedHeading;
  final int matchedSectionIndex;
  final String matchedCanonicalTitle;
  final double score;
  final String matchType;

  bool get isMatch => matchedSectionIndex >= 0 && score >= SectionMatchThresholds.minimumScore;
}

/// Compares one generated heading with current and later planned sections.
abstract final class LongFormSectionMatcher {
  static const _stopwords = <String>{
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

  static SectionMatch match({
    required String generatedHeading,
    required List<String> plannedSections,
    required int fromIndex,
  }) {
    final normalized = LongFormSectionPlan.normalizeHeading(generatedHeading);
    if (normalized.isEmpty || plannedSections.isEmpty) {
      return SectionMatch.none(normalized);
    }
    final start = fromIndex < 0 ? 0 : fromIndex;
    SectionMatch? best;
    for (var index = start; index < plannedSections.length; index++) {
      final candidate = _score(
        heading: normalized,
        title: LongFormSectionPlan.normalizeHeading(plannedSections[index]),
        index: index,
        canonicalTitle: plannedSections[index],
      );
      if (candidate == null) {
        continue;
      }
      if (best == null ||
          candidate.score > best.score ||
          (candidate.score == best.score && candidate.matchedSectionIndex < best.matchedSectionIndex)) {
        best = candidate;
      }
    }
    return best ?? SectionMatch.none(normalized);
  }

  static SectionMatch? _score({
    required String heading,
    required String title,
    required int index,
    required String canonicalTitle,
  }) {
    if (title.isEmpty || heading.isEmpty) {
      return null;
    }
    if (heading == title) {
      return SectionMatch(
        normalizedHeading: heading,
        matchedSectionIndex: index,
        matchedCanonicalTitle: canonicalTitle,
        score: SectionMatchThresholds.exact,
        matchType: 'exact',
      );
    }
    if (title.length < SectionMatchThresholds.minimumTitleChars) {
      return null;
    }
    if (heading.startsWith('$title ')) {
      return SectionMatch(
        normalizedHeading: heading,
        matchedSectionIndex: index,
        matchedCanonicalTitle: canonicalTitle,
        score: SectionMatchThresholds.prefix,
        matchType: 'prefix',
      );
    }
    final headingTokens = _contentTokens(heading);
    final titleTokens = _contentTokens(title);
    if (titleTokens.length == 1 &&
        title.length >= 4 &&
        headingTokens.isNotEmpty &&
        headingTokens.first.startsWith(titleTokens.first) &&
        headingTokens.first != titleTokens.first) {
      return SectionMatch(
        normalizedHeading: heading,
        matchedSectionIndex: index,
        matchedCanonicalTitle: canonicalTitle,
        score: SectionMatchThresholds.morphologicalPrefix,
        matchType: 'prefix',
      );
    }
    if (titleTokens.isNotEmpty && _containsInOrder(headingTokens, titleTokens)) {
      return SectionMatch(
        normalizedHeading: heading,
        matchedSectionIndex: index,
        matchedCanonicalTitle: canonicalTitle,
        score: SectionMatchThresholds.containment,
        matchType: 'containment',
      );
    }
    if (titleTokens.isNotEmpty) {
      final hits = titleTokens.where(headingTokens.contains).length;
      final ratio = hits / titleTokens.length;
      final strong = titleTokens.any(
        (token) => token.length >= SectionMatchThresholds.minimumTitleChars && headingTokens.contains(token),
      );
      if (strong && ratio >= SectionMatchThresholds.minimumTokenOverlapRatio) {
        return SectionMatch(
          normalizedHeading: heading,
          matchedSectionIndex: index,
          matchedCanonicalTitle: canonicalTitle,
          score: SectionMatchThresholds.tokenOverlap,
          matchType: 'token_overlap',
        );
      }
    }
    if (title.length >= SectionMatchThresholds.minimumLexicalTitleChars &&
        _bigramCoverage(title, heading) >= SectionMatchThresholds.minimumLexicalCoverage) {
      return SectionMatch(
        normalizedHeading: heading,
        matchedSectionIndex: index,
        matchedCanonicalTitle: canonicalTitle,
        score: SectionMatchThresholds.lexical,
        matchType: 'lexical',
      );
    }
    return null;
  }

  static List<String> _contentTokens(String normalized) {
    return normalized
        .split(' ')
        .where((token) => token.isNotEmpty && !_stopwords.contains(token))
        .toList(growable: false);
  }

  static bool _containsInOrder(List<String> haystack, List<String> needle) {
    var cursor = 0;
    for (final token in needle) {
      var found = false;
      while (cursor < haystack.length) {
        if (haystack[cursor] == token) {
          cursor += 1;
          found = true;
          break;
        }
        cursor += 1;
      }
      if (!found) {
        return false;
      }
    }
    return true;
  }

  static double _bigramCoverage(String needle, String haystack) {
    if (needle.length < 2) {
      return 0;
    }
    var hits = 0;
    final total = needle.length - 1;
    for (var index = 0; index < total; index++) {
      if (haystack.contains(needle.substring(index, index + 2))) {
        hits += 1;
      }
    }
    return hits / total;
  }
}

/// Drops orchestration instructions echoed by the model. Article text stays.
abstract final class LongFormOutputSanitizer {
  static String sanitize(
    String text, {
    String? originalPrompt,
    List<String> plannedSections = const [],
  }) {
    final planned = plannedSections
        .map(LongFormSectionPlan.normalizeHeading)
        .where((section) => section.isNotEmpty)
        .toSet();
    final promptKey = originalPrompt == null
        ? ''
        : LongFormSectionPlan.normalizeHeading(originalPrompt);
    final kept = <String>[];
    var dropEchoedPrompt = false;
    var inPlanner = false;
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (dropEchoedPrompt) {
        dropEchoedPrompt = false;
        if (promptKey.isNotEmpty &&
            LongFormSectionPlan.normalizeHeading(trimmed) == promptKey) {
          continue;
        }
      }
      if (_isOrchestrationLine(trimmed)) {
        if (LongFormSectionPlan.normalizeHeading(trimmed) == 'درخواست') {
          dropEchoedPrompt = true;
        }
        if (_isPlannerHeader(trimmed)) {
          inPlanner = true;
        }
        continue;
      }
      if (inPlanner) {
        if (trimmed.isEmpty || _isPlannerBullet(trimmed, planned)) {
          continue;
        }
        inPlanner = false;
      }
      if (trimmed.contains(LongFormSectionPlan.marker)) {
        final stripped = trimmed.replaceAll(LongFormSectionPlan.marker, '').trimRight();
        if (stripped.isEmpty) {
          continue;
        }
        kept.add(stripped);
        continue;
      }
      kept.add(line);
    }
    return kept.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trimRight();
  }

  static bool _isPlannerHeader(String trimmed) {
    final key = LongFormSectionPlan.normalizeHeading(trimmed);
    return key == 'completed sections' ||
        key == 'current section' ||
        key == 'remaining sections';
  }

  static bool _isPlannerBullet(String trimmed, Set<String> planned) {
    final key = LongFormSectionPlan.normalizeHeading(trimmed);
    return key == 'none' || planned.contains(key);
  }

  static bool _isOrchestrationLine(String trimmed) {
    if (trimmed.isEmpty) {
      return false;
    }
    if (trimmed == LongFormSectionPlan.marker) {
      return true;
    }
    final key = LongFormSectionPlan.normalizeHeading(trimmed);
    const exact = <String>{
      'درخواست',
      'ادامه متن',
      'completed sections',
      'current section',
      'remaining sections',
      'do not repeat completed sections',
      'append exactly',
    };
    if (exact.contains(key)) {
      return true;
    }
    return key.startsWith('continue only') ||
        key.startsWith('when and only when') ||
        key.startsWith('دقیقا از ادامه متن') ||
        key.startsWith('هیچ heading') ||
        key.startsWith('اگر آخر متن ناقص');
  }

  /// A marker copied from the continuation instructions is not document completion.
  static bool hasRealCompletionMarker(String text) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    for (var index = 0; index < lines.length; index++) {
      if (!lines[index].contains(LongFormSectionPlan.marker)) {
        continue;
      }
      final previous = index == 0 ? '' : lines[index - 1];
      final remainder = lines[index].replaceAll(LongFormSectionPlan.marker, '').trim();
      if (_isOrchestrationLine(previous) || _isOrchestrationLine(remainder)) {
        continue;
      }
      return true;
    }
    return false;
  }
}
