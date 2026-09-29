import 'device_constraints.dart';

class ConstraintBlockedException implements Exception {
  ConstraintBlockedException(this.violation, [this.detail]);

  final ConstraintViolation violation;
  final String? detail;

  @override
  String toString() => 'ConstraintBlockedException($violation, $detail)';
}

class StaleFenceException implements Exception {
  StaleFenceException(this.expected, this.actual);

  final int expected;
  final int actual;

  @override
  String toString() => 'StaleFenceException(expected=$expected, actual=$actual)';
}

/// Input manifest or content could not be fetched from the task URL.
class InputFetchException implements Exception {
  const InputFetchException.timeout(this.target)
      : timedOut = true,
        statusCode = null;

  const InputFetchException.unavailable(this.target, {this.statusCode}) : timedOut = false;

  final Uri target;
  final bool timedOut;
  final int? statusCode;

  @override
  String toString() => timedOut
      ? 'InputFetchException(timeout $target)'
      : 'InputFetchException(unavailable $target status=$statusCode)';
}

class ModelIntegrityException implements Exception {
  ModelIntegrityException(this.reason);

  final String reason;

  @override
  String toString() => 'ModelIntegrityException($reason)';
}

/// Raised before native LiteRT load when artifact format/engine mismatch.
class ModelFormatUnsupportedException implements Exception {
  ModelFormatUnsupportedException(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => 'ModelFormatUnsupportedException($code, $detail)';
}

class LeaseRevokedException implements Exception {
  const LeaseRevokedException();

  @override
  String toString() => 'LeaseRevokedException()';
}
