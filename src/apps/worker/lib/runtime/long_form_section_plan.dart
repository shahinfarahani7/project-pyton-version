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

  void advanceIfSectionClosed(String stageText) {
    if (plannedSectionsComplete || currentSection == null) {
      return;
    }
    if (LongFormSectionProgress.syntacticallyOpen(stageText)) {
      return;
    }
    currentIndex += 1;
  }

  /// Sentence/block shape only. This does not mean the document is finished.
  static bool syntacticallyOpen(String text) {
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) {
      return true;
    }
    const terminators = {'.', '!', '?', '؟', '。', '…'};
    return !terminators.contains(trimmed[trimmed.length - 1]);
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
