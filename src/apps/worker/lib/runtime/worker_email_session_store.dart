import 'dart:convert';

import 'encrypted_store.dart';

const _storageKey = 'worker_email_session_v1';

/// Signed-in email session. The password is never stored.
class WorkerEmailSession {
  const WorkerEmailSession({
    required this.email,
    required this.sessionPublicId,
    required this.expiresAtUtc,
    this.sessionCookie,
    this.csrfToken,
  });

  factory WorkerEmailSession.fromJson(Map<String, dynamic> json) {
    return WorkerEmailSession(
      email: json['email'] as String,
      sessionPublicId: json['sessionPublicId'] as String,
      expiresAtUtc: DateTime.parse(json['expiresAtUtc'] as String).toUtc(),
      sessionCookie: json['sessionCookie'] as String?,
      csrfToken: json['csrfToken'] as String?,
    );
  }

  final String email;
  final String sessionPublicId;
  final DateTime expiresAtUtc;
  final String? sessionCookie;
  final String? csrfToken;

  bool isActiveAt(DateTime now) => expiresAtUtc.isAfter(now.toUtc());

  Map<String, dynamic> toJson() => {
    'email': email,
    'sessionPublicId': sessionPublicId,
    'expiresAtUtc': expiresAtUtc.toUtc().toIso8601String(),
    if (sessionCookie != null) 'sessionCookie': sessionCookie,
    if (csrfToken != null) 'csrfToken': csrfToken,
  };

  @override
  String toString() =>
      'WorkerEmailSession(email: $email, sessionPublicId: $sessionPublicId)';
}

class WorkerEmailSessionStore {
  WorkerEmailSessionStore(this._store);

  final EncryptedStore _store;

  Future<WorkerEmailSession?> read() async {
    final bytes = await _store.read(_storageKey);
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      return null;
    }
    return WorkerEmailSession.fromJson(decoded.cast<String, dynamic>());
  }

  Future<void> write(WorkerEmailSession session) async {
    await _store.write(_storageKey, utf8.encode(jsonEncode(session.toJson())));
  }

  Future<void> clear() async {
    await _store.delete(_storageKey);
  }
}
