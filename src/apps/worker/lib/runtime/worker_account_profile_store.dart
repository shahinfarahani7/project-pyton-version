import 'dart:convert';

import 'encrypted_store.dart';

const _storageKey = 'worker_account_profile_v1';

/// Username and email for display; synced to server when an account API exists.
/// Passwords are never stored — only changed through a server round-trip.
class WorkerAccountProfile {
  const WorkerAccountProfile({
    required this.username,
    required this.email,
    required this.updatedAtUtc,
  });

  factory WorkerAccountProfile.fromJson(Map<String, dynamic> json) {
    return WorkerAccountProfile(
      username: json['username'] as String,
      email: json['email'] as String,
      updatedAtUtc: DateTime.parse(json['updatedAtUtc'] as String),
    );
  }

  final String username;
  final String email;
  final DateTime updatedAtUtc;

  Map<String, dynamic> toJson() => {
        'username': username,
        'email': email,
        'updatedAtUtc': updatedAtUtc.toUtc().toIso8601String(),
      };

  String get maskedEmail {
    final value = email.trim();
    final at = value.indexOf('@');
    if (at <= 1) {
      return '••••';
    }
    return '${value.substring(0, 1)}•••@${value.substring(at + 1)}';
  }
}

class WorkerAccountProfileStore {
  WorkerAccountProfileStore(this._store);

  final EncryptedStore _store;

  Future<WorkerAccountProfile?> read() async {
    final bytes = await _store.read(_storageKey);
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      return null;
    }
    return WorkerAccountProfile.fromJson(decoded.cast<String, dynamic>());
  }

  Future<void> write(WorkerAccountProfile profile) async {
    await _store.write(_storageKey, utf8.encode(jsonEncode(profile.toJson())));
  }

  Future<void> clear() async {
    await _store.delete(_storageKey);
  }
}

/// Basic email shape check; server remains authoritative when connected.
bool isPlausibleEmail(String value) {
  final trimmed = value.trim();
  if (trimmed.length < 5 || trimmed.length > 254) {
    return false;
  }
  final at = trimmed.indexOf('@');
  if (at < 1 || at >= trimmed.length - 3) {
    return false;
  }
  return trimmed.contains('.');
}

/// Local validation before a future server password change call.
String? validateNewPassword({
  required String newPassword,
  required String confirmPassword,
}) {
  if (newPassword.length < 12) {
    return 'Use at least 12 characters.';
  }
  if (newPassword != confirmPassword) {
    return 'New passwords do not match.';
  }
  return null;
}
