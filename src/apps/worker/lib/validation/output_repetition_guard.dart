/// Detects a reply that has started looping so the decode can be stopped.
///
/// A 0.5B model that runs out of distinct facts keeps emitting the same short
/// phrase until the output budget is spent — one observed reply repeated
/// `"the milk arrived on time"` twelve times and never reached the remaining
/// fields. Stopping at the third repeat leaves those tokens for nothing and
/// makes the salvage path cheaper.
class OutputRepetitionGuard {
  OutputRepetitionGuard({
    this.windowChars = 32,
    this.minRepeats = 3,
    this.checkEveryChars = 24,
  });

  /// Length of the tail compared against the rest of the reply. Must exceed a
  /// looping phrase so one window covers a whole period of the loop.
  final int windowChars;

  final int minRepeats;

  /// The comparison only runs once per this many new characters.
  final int checkEveryChars;

  final StringBuffer _normalized = StringBuffer();
  int _length = 0;
  int _lastCheckedLength = 0;

  /// True once the tail of the reply has occurred [minRepeats] times.
  bool feed(String fragment) {
    if (fragment.isEmpty) {
      return false;
    }
    final normalized = fragment.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    _normalized.write(normalized);
    _length += normalized.length;
    if (_length < windowChars * minRepeats ||
        _length - _lastCheckedLength < checkEveryChars) {
      return false;
    }
    _lastCheckedLength = _length;

    final text = _normalized.toString();
    final window = text.substring(text.length - windowChars);
    // Occurrences are counted overlapping: a looping phrase is usually shorter
    // than the window, so skipping a whole window ahead would step over the
    // next repeat and hide the loop.
    var count = 0;
    var index = text.indexOf(window);
    while (index >= 0) {
      count += 1;
      if (count >= minRepeats) {
        return true;
      }
      index = text.indexOf(window, index + 1);
    }
    return false;
  }
}
