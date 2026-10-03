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

  /// One heading identity for markdown, bold, spacing, punctuation, and case.
  static String normalizeHeading(String raw) {
    var text = raw.trim().toLowerCase();
    text = text.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u200c\u200d\u00ad]'), '');
    text = text.replaceAll('ي', 'ی').replaceAll('ك', 'ک').replaceAll('ة', 'ه');
    text = text.replaceAll('\u00a0', ' ');
    text = text.replaceFirst(RegExp(r'^(?:#{1,6}[ \t]*)+'), '');
    text = text.replaceFirst(RegExp(r'^[-*+][ \t]+'), '');
    text = text.replaceAll(RegExp(r'[*_`]+'), '');
    text = text.replaceAll(
      RegExp(r'''[.,:;!?؟،؛。…:："'"“”«»()\[\]{}<>|\\/+\-–—]+'''),
      ' ',
    );
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }

  static LongFormSectionCleanup removeDuplicateSections({
    required String text,
    required List<String> plannedSections,
    required List<String> completedSections,
    String previousText = '',
  }) {
    final headingIndex = <String, int>{};
    for (var index = 0; index < plannedSections.length; index++) {
      final key = normalizeHeading(plannedSections[index]);
      if (key.isNotEmpty) {
        headingIndex[key] = index;
      }
    }
    for (final section in completedSections) {
      final key = normalizeHeading(section);
      if (key.isNotEmpty) {
        headingIndex.putIfAbsent(key, () => headingIndex.length);
      }
    }
    if (headingIndex.isEmpty) {
      return LongFormSectionCleanup(text, 0);
    }
    final completed = completedSections.map(normalizeHeading).toSet();
    final alreadyInPrevious = <String>{};
    for (final line in previousText.split('\n')) {
      final key = normalizeHeading(line);
      if (headingIndex.containsKey(key)) {
        alreadyInPrevious.add(key);
      }
    }
    final seen = <String>{};
    final kept = <String>[];
    var skipping = false;
    var removed = 0;
    for (final line in text.split('\n')) {
      final key = normalizeHeading(line);
      final isHeading = key.isNotEmpty && headingIndex.containsKey(key);
      if (isHeading) {
        if (completed.contains(key) || seen.contains(key)) {
          skipping = true;
          removed += 1;
          continue;
        }
        if (alreadyInPrevious.contains(key)) {
          seen.add(key);
          removed += 1;
          skipping = false;
          continue;
        }
        seen.add(key);
        skipping = false;
        kept.add(line);
        continue;
      }
      if (skipping) {
        continue;
      }
      kept.add(line);
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

  /// Moves the cursor to the furthest section heading actually started.
  /// Earlier sections stay completed. The cursor never moves backward.
  void observe(String stageText) {
    if (plannedSectionsComplete || plannedSections.isEmpty) {
      return;
    }
    final indexByHeading = <String, int>{};
    for (var index = 0; index < plannedSections.length; index++) {
      final key = LongFormSectionPlan.normalizeHeading(plannedSections[index]);
      if (key.isNotEmpty) {
        indexByHeading[key] = index;
      }
    }
    var furthest = currentIndex;
    for (final line in stageText.split('\n')) {
      final index = indexByHeading[LongFormSectionPlan.normalizeHeading(line)];
      if (index != null && index > furthest) {
        furthest = index;
      }
    }
    currentIndex = furthest;
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
