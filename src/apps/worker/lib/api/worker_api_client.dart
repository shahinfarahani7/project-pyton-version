import 'dart:convert';

import 'package:http/http.dart' as http;

import 'worker_assignment_models.dart';
import '../config/worker_config.dart';
import 'worker_routes.dart';

typedef WorkerApiAuditCallback = void Function({
  required String method,
  required String path,
  required int status,
});

class WorkerApiException implements Exception {
  WorkerApiException({
    required this.method,
    required this.path,
    required this.statusCode,
    required this.code,
    this.detail,
  });

  final String method;
  final String path;
  final int statusCode;
  final String code;
  final String? detail;

  bool get isNotFound => statusCode == 404;

  @override
  String toString() {
    final detailSuffix =
        detail != null && detail!.isNotEmpty ? ', detail=$detail' : '';
    return 'WorkerApiException('
        'method=$method, '
        'path=$path, '
        'status=$statusCode, '
        'code=$code'
        '$detailSuffix'
        ')';
  }
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
  WorkerApiClient({
    WorkerConfig? config,
    http.Client? httpClient,
    WorkerApiAuditCallback? onAudit,
    this.devClaimAssignments = false,
  })  : _config = config ?? WorkerConfig.fromEnvironment(),
        _http = httpClient ?? http.Client(),
        _onAudit = onAudit;

  final WorkerConfig _config;
  final http.Client _http;
  final WorkerApiAuditCallback? _onAudit;

  /// When true, dev worker-gateway pins assignments to this device on first poll.
  bool devClaimAssignments;

  void reconfigure(WorkerConfig config) {
    _config.baseUrl = config.baseUrl;
  }

  Future<DeviceChallenge> createDeviceChallenge({
    required String installationId,
    required String idempotencyKey,
    String? requestId,
  }) async {
    const path = WorkerRoutes.createChallenge;
    final response = await _post(
      path,
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
    const path = WorkerRoutes.registerDevice;
    final response = await _post(
      path,
      body: payload,
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
    return WorkerRegistration.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<WorkerRegistration> refreshWorkerSession({
    required String refreshToken,
    required String idempotencyKey,
    String? requestId,
  }) async {
    const path = WorkerRoutes.refreshSession;
    final response = await _post(
      path,
      body: {'refreshToken': refreshToken},
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
    return WorkerRegistration.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<CommandReceipt> submitBenchmark({
    required String workerId,
    required String accessToken,
    required Map<String, dynamic> body,
    required String idempotencyKey,
    String? requestId,
  }) async {
    final path = WorkerRoutes.workerBenchmark(workerId);
    final response = await _post(
      path,
      body: body,
      accessToken: accessToken,
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
    return CommandReceipt.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getWorkerPreferences({
    required String accessToken,
    String? requestId,
  }) async {
    const path = WorkerRoutes.workerPreferences;
    final response = await _get(
      path,
      accessToken: accessToken,
      requestId: requestId,
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<CommandReceipt> replaceWorkerPreferences({
    required String accessToken,
    required Map<String, dynamic> body,
    required String idempotencyKey,
    String? requestId,
  }) async {
    const path = WorkerRoutes.workerPreferences;
    final response = await _put(
      path,
      body: body,
      accessToken: accessToken,
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
    return CommandReceipt.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<CommandReceipt> sendHeartbeat({
    required String workerId,
    required String accessToken,
    required Map<String, dynamic> body,
    required String idempotencyKey,
    String? requestId,
  }) async {
    final path = WorkerRoutes.workerHeartbeat(workerId);
    final response = await _post(
      path,
      body: body,
      accessToken: accessToken,
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
    return CommandReceipt.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ModelManifestView> getModelManifest({
    required String modelVersionId,
    required String accessToken,
    String? requestId,
  }) async {
    final path = WorkerRoutes.modelManifest(modelVersionId);
    final response = await _get(
      path,
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
    final path = WorkerRoutes.reportModelInstall(modelVersionId);
    await _post(
      path,
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
    const path = WorkerRoutes.nextAssignment;
    final timeout = waitSeconds > 0
        ? Duration(seconds: waitSeconds + 15)
        : _config.requestTimeout;
    final response = await _http
        .get(
          _config.resolve(path).replace(queryParameters: {
            if (waitSeconds > 0) 'waitSeconds': '$waitSeconds',
          }),
          headers: _headers(
            accessToken: accessToken,
            requestId: requestId,
            extra: devClaimAssignments
                ? const {'X-EdgeMint-Dev-Claim-Assignments': '1'}
                : null,
          ),
        )
        .timeout(timeout);
    _audit('GET', path, response.statusCode);
    if (response.statusCode == 204) {
      return null;
    }
    _ensureSuccess(response, method: 'GET', path: path);
    return WorkerAssignment.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getAssignmentInboxBootstrap({
    required String accessToken,
    String? requestId,
  }) async {
    const path = WorkerRoutes.assignmentInboxBootstrap;
    final response = await _get(
      path,
      accessToken: accessToken,
      requestId: requestId,
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<CommandReceipt> reportAssignmentStarted({
    required String assignmentId,
    required String accessToken,
    required String leaseToken,
    required int fenceToken,
    required String idempotencyKey,
    String? requestId,
  }) async {
    final path = WorkerRoutes.reportAssignmentStarted(assignmentId);
    final response = await _post(
      path,
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
    final path = WorkerRoutes.renewAssignment(assignmentId);
    final response = await _post(
      path,
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
    final path = WorkerRoutes.progressAssignment(assignmentId);
    final response = await _post(
      path,
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
    final path = WorkerRoutes.checkpointAssignment(assignmentId);
    final response = await _post(
      path,
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
    final path = WorkerRoutes.completeAssignment(assignmentId);
    final response = await _post(
      path,
      body: body,
      accessToken: accessToken,
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
    return CommandReceipt.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<CommandReceipt> failAssignment({
    required String assignmentId,
    required String accessToken,
    required Map<String, dynamic> body,
    required String idempotencyKey,
    String? requestId,
  }) async {
    final path = WorkerRoutes.failAssignment(assignmentId);
    final response = await _post(
      path,
      body: body,
      accessToken: accessToken,
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
    return CommandReceipt.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<CommandReceipt> confirmPhysicalStop({
    required String assignmentId,
    required String accessToken,
    required String leaseToken,
    required int fenceToken,
    required String proof,
    required String idempotencyKey,
    String reason = 'worker_stop_confirmed',
    String? requestId,
  }) async {
    final path = WorkerRoutes.confirmPhysicalStop(assignmentId);
    final response = await _post(
      path,
      body: {
        'leaseToken': leaseToken,
        'fenceToken': fenceToken,
        'proof': proof,
        'reason': reason,
      },
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
    final path = WorkerRoutes.abandonAssignment(assignmentId);
    final response = await _post(
      path,
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
    _audit('GET', path, response.statusCode);
    _ensureSuccess(response, method: 'GET', path: path);
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
    _audit('POST', path, response.statusCode);
    _ensureSuccess(response, method: 'POST', path: path);
    return response;
  }

  Future<http.Response> _put(
    String path, {
    required Map<String, dynamic> body,
    String? accessToken,
    required String idempotencyKey,
    String? requestId,
  }) async {
    final response = await _http
        .put(
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
    _audit('PUT', path, response.statusCode);
    _ensureSuccess(response, method: 'PUT', path: path);
    return response;
  }

  Map<String, String> _headers({
    String? accessToken,
    String? idempotencyKey,
    String? requestId,
    bool json = false,
    Map<String, String>? extra,
  }) {
    return {
      if (json) 'Content-Type': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      if (requestId != null) 'X-Request-Id': requestId,
      ...?extra,
    };
  }

  void _audit(String method, String path, int status) {
    _onAudit?.call(method: method, path: path, status: status);
  }

  void _ensureSuccess(
    http.Response response, {
    required String method,
    required String path,
  }) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    String code = 'HTTP_${response.statusCode}';
    String? detail;
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        code = body['code'] as String? ?? code;
        detail = body['detail'] as String? ?? body['title'] as String?;
        if (detail == null && body['detail'] is List) {
          detail = 'validation failed';
        }
      }
    } catch (_) {
      if (response.reasonPhrase != null && response.reasonPhrase!.isNotEmpty) {
        detail = response.reasonPhrase;
      }
    }
    throw WorkerApiException(
      method: method,
      path: path,
      statusCode: response.statusCode,
      code: code,
      detail: detail,
    );
  }

  void close() => _http.close();
}
