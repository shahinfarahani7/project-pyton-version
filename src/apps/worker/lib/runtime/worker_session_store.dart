import 'dart:convert';

import 'encrypted_store.dart';

/// Persisted worker enrollment credentials (encrypted at rest on device).
class WorkerSessionRecord {
  const WorkerSessionRecord({
    required this.workerId,
    required this.deviceId,
    required this.accessToken,
    required this.expiresAt,
    required this.installationId,
    this.benchmarkSubmitted = false,
    this.lastHeartbeatSequence = 0,
  });

  factory WorkerSessionRecord.fromJson(Map<String, dynamic> json) => WorkerSessionRecord(
        workerId: json['workerId'] as String,
        deviceId: json['deviceId'] as String,
        accessToken: json['accessToken'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        installationId: json['installationId'] as String,
        benchmarkSubmitted: json['benchmarkSubmitted'] as bool? ?? false,
        lastHeartbeatSequence: json['lastHeartbeatSequence'] as int? ?? 0,
      );

  final String workerId;
  final String deviceId;
  final String accessToken;
  final DateTime expiresAt;
  final String installationId;
  final bool benchmarkSubmitted;
  final int lastHeartbeatSequence;

  bool get isExpired => expiresAt.isBefore(DateTime.now().toUtc());

  bool expiresWithin(Duration window) =>
      expiresAt.isBefore(DateTime.now().toUtc().add(window));

  WorkerSessionRecord copyWith({
    String? workerId,
    String? deviceId,
    String? accessToken,
    DateTime? expiresAt,
    String? installationId,
    bool? benchmarkSubmitted,
    int? lastHeartbeatSequence,
  }) {
    return WorkerSessionRecord(
      workerId: workerId ?? this.workerId,
      deviceId: deviceId ?? this.deviceId,
      accessToken: accessToken ?? this.accessToken,
      expiresAt: expiresAt ?? this.expiresAt,
      installationId: installationId ?? this.installationId,
      benchmarkSubmitted: benchmarkSubmitted ?? this.benchmarkSubmitted,
      lastHeartbeatSequence: lastHeartbeatSequence ?? this.lastHeartbeatSequence,
    );
  }

  Map<String, dynamic> toJson() => {
        'workerId': workerId,
        'deviceId': deviceId,
        'accessToken': accessToken,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'installationId': installationId,
        'benchmarkSubmitted': benchmarkSubmitted,
        'lastHeartbeatSequence': lastHeartbeatSequence,
      };
}

/// Encrypted persistence for installation id and worker session credentials.
class WorkerSessionStore {
  WorkerSessionStore(this._store);

  static const sessionKey = 'worker_session_v1';
  static const installationKey = 'worker_installation_id_v1';

  final EncryptedStore _store;

  Future<WorkerSessionRecord?> readSession() async {
    final raw = await _store.read(sessionKey);
    if (raw == null) {
      return null;
    }
    return WorkerSessionRecord.fromJson(
      jsonDecode(utf8.decode(raw)) as Map<String, dynamic>,
    );
  }

  Future<void> writeSession(WorkerSessionRecord session) async {
    await _store.write(sessionKey, utf8.encode(jsonEncode(session.toJson())));
  }

  Future<void> clearSession() async {
    await _store.delete(sessionKey);
  }

  Future<String> readOrCreateInstallationId() async {
    final existing = await _store.read(installationKey);
    if (existing != null) {
      return utf8.decode(existing);
    }
    final created = _newInstallationId();
    await _store.write(installationKey, utf8.encode(created));
    return created;
  }

  String _newInstallationId() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return 'inst_$stamp';
  }
}
