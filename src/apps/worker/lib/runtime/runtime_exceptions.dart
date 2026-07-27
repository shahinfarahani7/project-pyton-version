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

class ModelIntegrityException implements Exception {
  ModelIntegrityException(this.reason);

  final String reason;

  @override
  String toString() => 'ModelIntegrityException($reason)';
}

class LeaseRevokedException implements Exception {
  const LeaseRevokedException();

  @override
  String toString() => 'LeaseRevokedException()';
}
