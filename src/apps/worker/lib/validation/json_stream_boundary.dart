/// Tracks streamed model output and reports when a complete top-level JSON
/// object has been produced.
///
/// `maxOutputTokens` is ignored by the MediaPipe `.task` path, so the decode
/// loop only stops at the model sequence limit. Detecting the closing brace
/// lets the caller invoke the runtime stop mechanism instead (v2 §25).
class JsonObjectBoundaryScanner {
  int _depth = 0;
  bool _inString = false;
  bool _escaped = false;
  bool _opened = false;
  bool _complete = false;

  bool get isComplete => _complete;

  /// Feeds the next streamed fragment and returns whether the object closed.
  bool feed(String chunk) {
    if (_complete) {
      return true;
    }
    for (var index = 0; index < chunk.length; index++) {
      final char = chunk[index];
      if (_inString) {
        if (_escaped) {
          _escaped = false;
        } else if (char == r'\') {
          _escaped = true;
        } else if (char == '"') {
          _inString = false;
        }
        continue;
      }
      switch (char) {
        case '"':
          _inString = true;
        case '{':
          _depth += 1;
          _opened = true;
        case '}':
          _depth -= 1;
          if (_opened && _depth <= 0) {
            _complete = true;
            return true;
          }
      }
    }
    return false;
  }
}
