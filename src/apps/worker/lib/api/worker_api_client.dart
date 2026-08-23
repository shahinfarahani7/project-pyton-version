import 'dart:convert';

import 'package:http/http.dart' as http;

import 'worker_assignment_models.dart';
import '../config/worker_config.dart';
import 'worker_routes.dart';

class WorkerApiException implements Exception {
  WorkerApiException(this.statusCode, this.code, [this.detail]);

  final int statusCode;
  final String code;
  final String? detail;

  @override
  String toString() => 'WorkerApiException($statusCode, $code, $detail)';
}

class DeviceChallenge {
  DeviceChallenge({required this.challengeId, required this.nonce, required this.expiresAt});

  factory DeviceChallenge.fromJson(Map<String, dynamic> json) => DeviceChallenge(
        challengeId: json['challengeId'] as String,
        nonce: json['nonce'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );

  final String challengeId;
  final String nonce;
  final DateTime expiresAt;
}

class WorkerRegistration {
  WorkerRegistration({
    required this.workerId,
    required this.deviceId,
    required this.accessToken,
    required this.expiresAt,
  });

  factory WorkerRegistration.fromJson(Map<String, dynamic> json) => WorkerRegistration(
        workerId: json['workerId'] as String,
        deviceId: json['deviceId'] as String,
        accessToken: json['accessToken'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );

  final String workerId;
  final String deviceId;
  final String accessToken;
  final DateTime expiresAt;
}

class ModelManifestView {
  ModelManifestView({
    required this.id,
    required this.status,
    required this.version,
    required this.updatedAt,
  });

  factory ModelManifestView.fromJson(Map<String, dynamic> json) => ModelManifestView(
        id: json['id'] as String,
        status: json['status'] as String,
        version: json['version'] as int,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  final String id;
  final String status;
  final int version;
  final DateTime updatedAt;
}

class WorkerApiClient {
  WorkerApiClient({WorkerConfig? config, http.Client? httpClient})
      : _config = config ?? WorkerConfig.fromEnvironment(),
        _http = httpClient ?? http.Client();

  final WorkerConfig _config;
  final http.Client _http;

  void reconfigure(WorkerConfig config) {
    _config.baseUrl = config.baseUrl;
  }

  Future<DeviceChallenge> createDeviceChallenge({
    required String installationId,
    required String idempotencyKey,
    String? requestId,
  }) async {
    final response = await _post(
      WorkerRoutes.createChallenge,
      body: {'installationId': installationId},
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
    return DeviceChallenge.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<WorkerRegistration> registerWorkerDevice({
    required Map<String, dynamic> payload,
    required String idempotencyKey,
    String? requestId,
  }) async {
    final response = await _post(
      WorkerRoutes.registerDevice,
      body: payload,
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
    return WorkerRegistration.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ModelManifestView> getModelManifest({
    required String modelVersionId,
    required String accessToken,
    String? requestId,
  }) async {
    final response = await _get(
      WorkerRoutes.modelManifest(modelVersionId),
      accessToken: accessToken,
      requestId: requestId,
    );
    return ModelManifestView.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> reportModelInstall({
    required String modelVersionId,
    required String accessToken,
    required String artifactSha256,
    required String status,
    required String idempotencyKey,
    String? requestId,
  }) async {
    await _post(
      WorkerRoutes.reportModelInstall(modelVersionId),
      body: {'artifactSha256': artifactSha256, 'status': status},
      accessToken: accessToken,
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
  }

  Future<WorkerAssignment?> getNextAssignment({
    required String accessToken,
    int waitSeconds = 0,
    String? requestId,
  }) async {
    final timeout = waitSeconds > 0
        ? Duration(seconds: waitSeconds + 15)
        : _config.requestTimeout;
    final response = await _http
        .get(
          _config.resolve(WorkerRoutes.nextAssignment).replace(queryParameters: {
            if (waitSeconds > 0) 'waitSeconds': '$waitSeconds',
          }),
          headers: _headers(accessToken: accessToken, requestId: requestId),
        )
        .timeout(timeout);
    if (response.statusCode == 204) {
      return null;
    }
    _ensureSuccess(response);
    return WorkerAssignment.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<CommandReceipt> reportAssignmentStarted({
    required String assignmentId,
    required String accessToken,
    required String leaseToken,
    required int fenceToken,
    required String idempotencyKey,
    String? requestId,
  }) async {
    final response = await _post(
      WorkerRoutes.reportAssignmentStarted(assignmentId),
      body: {'leaseToken': leaseToken, 'fenceToken': fenceToken},
      accessToken: accessToken,
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
    return CommandReceipt.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<CommandReceipt> renewAssignment({
    required String assignmentId,
    required String accessToken,
    required String leaseToken,
    required int fenceToken,
    required int sequence,
    required String idempotencyKey,
    String? requestId,
  }) async {
    final response = await _post(
      WorkerRoutes.renewAssignment(assignmentId),
      body: {
        'leaseToken': leaseToken,
        'fenceToken': fenceToken,
        'sequence': sequence,
      },
      accessToken: accessToken,
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
    return CommandReceipt.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<CommandReceipt> progressAssignment({
    required String assignmentId,
    required String accessToken,
    required Map<String, dynamic> body,
    required String idempotencyKey,
    String? requestId,
  }) async {
    final response = await _post(
      WorkerRoutes.progressAssignment(assignmentId),
      body: body,
      accessToken: accessToken,
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
    return CommandReceipt.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<CommandReceipt> checkpointAssignment({
    required String assignmentId,
    required String accessToken,
    required Map<String, dynamic> body,
    required String idempotencyKey,
    String? requestId,
  }) async {
    final response = await _post(
      WorkerRoutes.checkpointAssignment(assignmentId),
      body: body,
      accessToken: accessToken,
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
    return CommandReceipt.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<CommandReceipt> completeAssignment({
    required String assignmentId,
    required String accessToken,
    required Map<String, dynamic> body,
    required String idempotencyKey,
    String? requestId,
  }) async {
    final response = await _post(
      WorkerRoutes.completeAssignment(assignmentId),
      body: body,
      accessToken: accessToken,
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
    return CommandReceipt.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<CommandReceipt> abandonAssignment({
    required String assignmentId,
    required String accessToken,
    required String leaseToken,
    required int fenceToken,
    required String reason,
    required String idempotencyKey,
    String? requestId,
  }) async {
    final response = await _post(
      WorkerRoutes.abandonAssignment(assignmentId),
      body: {'leaseToken': leaseToken, 'fenceToken': fenceToken, 'reason': reason},
      accessToken: accessToken,
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
    return CommandReceipt.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<http.Response> _get(
    String path, {
    required String accessToken,
    String? requestId,
  }) async {
    final response = await _http
        .get(
          _config.resolve(path),
          headers: _headers(accessToken: accessToken, requestId: requestId),
        )
        .timeout(_config.requestTimeout);
    _ensureSuccess(response);
    return response;
  }

  Future<http.Response> _post(
    String path, {
    required Map<String, dynamic> body,
    String? accessToken,
    required String idempotencyKey,
    String? requestId,
  }) async {
    final response = await _http
        .post(
          _config.resolve(path),
          headers: _headers(
            accessToken: accessToken,
            idempotencyKey: idempotencyKey,
            requestId: requestId,
            json: true,
          ),
          body: jsonEncode(body),
        )
        .timeout(_config.requestTimeout);
    _ensureSuccess(response);
    return response;
  }

  Map<String, String> _headers({
    String? accessToken,
    String? idempotencyKey,
    String? requestId,
    bool json = false,
  }) {
    return {
      if (json) 'Content-Type': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      'Idempotency-Key': ?idempotencyKey,
      'X-Request-Id': ?requestId,
    };
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    String code = 'HTTP_${response.statusCode}';
    String? detail;
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      code = body['code'] as String? ?? code;
      detail = body['detail'] as String?;
    } catch (_) {}
    throw WorkerApiException(response.statusCode, code, detail);
  }

  void close() => _http.close();
}
