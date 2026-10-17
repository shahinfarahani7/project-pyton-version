import 'package:edgemint_worker/runtime/worker_account_profile_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isPlausibleEmail', () {
    test('accepts typical addresses', () {
      expect(isPlausibleEmail('user@example.com'), isTrue);
    });

    test('rejects missing domain', () {
      expect(isPlausibleEmail('user@localhost'), isFalse);
    });
  });

  group('validateNewPassword', () {
    test('requires minimum length', () {
      expect(
        validateNewPassword(newPassword: 'short', confirmPassword: 'short'),
        isNotNull,
      );
    });

    test('requires matching confirmation', () {
      expect(
        validateNewPassword(
          newPassword: 'long-enough-pass',
          confirmPassword: 'other-long-pass',
        ),
        isNotNull,
      );
    });

    test('accepts valid pair', () {
      expect(
        validateNewPassword(
          newPassword: 'long-enough-pass',
          confirmPassword: 'long-enough-pass',
        ),
        isNull,
      );
    });
  });
}
