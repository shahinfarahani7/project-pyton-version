/// One-shot rule for portal `text.direct`.
///
/// The customer submits a task and reads the answer. They cannot reply in
/// the same conversation; a later message is a new task. The model must not
/// ask them anything or invite another turn.
abstract final class DirectAnswerInstruction {
  static const system = '''
You are answering one submitted task. This chat cannot continue. Another request is a new task.
Give the complete answer in this reply, in the user's language.
Do not ask the user any question. Do not request clarification. Do not offer a follow-up, more detail, or another turn.
Do not end with lines such as "Would you like...", "Let me know if...", "آیا سؤال دیگری دارید؟", or "اگر خواستید ادامه بدهم".
If the requested answer itself contains questions, include only those questions. Do not add one of your own.
''';

  static const userTurnMarker = '[single-turn]';

  static const userTurnRule =
      '''
$userTurnMarker
Reply in full now. Do not ask the user a question or invite a follow-up. The user cannot reply.
''';

  /// Appends the one-shot rule once. Continuation prompts that already include
  /// the original request keep a single copy.
  static String attach(String prompt) {
    if (prompt.contains(userTurnMarker)) {
      return prompt;
    }
    final body = prompt.trimRight();
    if (body.isEmpty) {
      return userTurnRule.trim();
    }
    return '$body\n\n$userTurnRule';
  }

  /// Drops a short trailing invitation. Leaves the answer unchanged when the
  /// invitation is the whole reply, so a requested question is not erased.
  static String stripTrailingInvitation(String text) {
    var result = text.trimRight();
    for (var i = 0; i < 3; i++) {
      final next = _stripOnce(result);
      if (next == null) {
        break;
      }
      result = next;
    }
    return result;
  }

  static String? _stripOnce(String text) {
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) {
      return null;
    }
    final paragraphs = trimmed.split(RegExp(r'\n\s*\n'));
    if (paragraphs.length >= 2 && _isInvitation(paragraphs.last)) {
      final head = paragraphs
          .sublist(0, paragraphs.length - 1)
          .join('\n\n')
          .trimRight();
      if (head.isNotEmpty) {
        return head;
      }
    }
    final lines = trimmed.split('\n');
    if (lines.length >= 2 && _isInvitation(lines.last)) {
      final head = lines.sublist(0, lines.length - 1).join('\n').trimRight();
      if (head.isNotEmpty) {
        return head;
      }
    }
    final sentence = _splitLastSentence(trimmed);
    if (sentence != null && _isInvitation(sentence.last)) {
      return sentence.head;
    }
    return null;
  }

  static bool _isInvitation(String raw) {
    final text = raw.trim();
    if (text.isEmpty || text.length > 280) {
      return false;
    }
    if (text.contains(userTurnMarker)) {
      return true;
    }
    if (text.contains('از کاربر سؤال نپرس') ||
        text.contains('از کاربر سوال نپرس')) {
      return true;
    }
    for (final pattern in _invitationPatterns) {
      if (pattern.hasMatch(text)) {
        return true;
      }
    }
    return false;
  }

  static final List<RegExp> _invitationPatterns = [
    RegExp('(?:سوال|سؤال)\\s*دیگر'),
    RegExp('اگر\\s+(?:خواستی|خواستید|سوال|سؤال|مایل)'),
    RegExp('می[\\u200c\\s]?خواه(?:ی|ید)\\s+(?:بیشتر|ادامه|توضیح)'),
    RegExp('آیا\\s+(?:مایل|می\\s?خواهید|می‌خواهید|سوال|سؤال)'),
    RegExp('بگو(?:یید|یید|ید)\\s+تا'),
    RegExp('در خدمتم'),
    RegExp('چیز دیگری|مورد دیگری'),
    RegExp(
      r"\b(?:would you like me to|do you want me to|shall i|let me know if|"
      r"any other questions?|anything else i can|feel free to ask|"
      r"if you have any (?:other|further) questions?|"
      r"would you like (?:more|another|a follow-up|a follow up))\b",
      caseSensitive: false,
    ),
  ];

  static _SentenceSplit? _splitLastSentence(String text) {
    final pattern = RegExp('[.!?؟]["»”\']?(?=\\s)');
    final matches = pattern.allMatches(text).toList();
    if (matches.isEmpty) {
      return null;
    }
    final end = matches.last.end;
    final head = text.substring(0, end).trimRight();
    final last = text.substring(end).trim();
    if (head.isEmpty || last.isEmpty) {
      return null;
    }
    return _SentenceSplit(head, last);
  }
}

class _SentenceSplit {
  const _SentenceSplit(this.head, this.last);

  final String head;
  final String last;
}
