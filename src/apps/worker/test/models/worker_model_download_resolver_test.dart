import 'dart:convert';

import 'package:edgemint_worker/api/worker_api_client.dart';
import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/config/worker_model_download_policy.dart';
import 'package:edgemint_worker/models/worker_model_catalog.dart';
import 'package:edgemint_worker/models/worker_model_download_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _RecordingClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  String? lastPath;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    lastPath = request.url.path;
    if (request.url.path.contains('/artifact-delivery')) {
      final payload = jsonEncode({
        'modelVersionId': WorkerModelCatalog.modelVersionId,
        'fileName': WorkerModelCatalog.fileName,
        'downloadPath':
            '/models/${WorkerModelCatalog.modelVersionId}/files/${WorkerModelCatalog.fileName}',
        'artifactSha256': WorkerModelCatalog.knownGeneralArtifactSha256,
        'sizeBytes': WorkerModelCatalog.knownGeneralArtifactSizeBytes,
      });
      return Future.value(
        http.StreamedResponse(
          Stream.value(utf8.encode(payload)),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      );
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

void main() {
  test('static direct resolves Hugging Face URL', () {
    final url = WorkerModelDownloadResolver.resolveStatic(
      config: WorkerConfig(baseUrl: Uri.parse('http://127.0.0.1:8081')),
      source: WorkerModelDownloadSource.direct,
    );
    expect(url, WorkerModelCatalog.huggingFaceDownloadUrl);
  });

  test('static backend proxy uses gateway file path', () {
    final url = WorkerModelDownloadResolver.resolveStatic(
      config: WorkerConfig(
        baseUrl: Uri.parse('http://127.0.0.1:8081'),
        modelDownloadSource: WorkerModelDownloadSource.backendProxy,
      ),
      source: WorkerModelDownloadSource.backendProxy,
    );
    expect(
      url,
      'http://127.0.0.1:8081/models/${WorkerModelCatalog.modelVersionId}/files/${WorkerModelCatalog.fileName}',
    );
  });

  test('server source fetches artifact-delivery and resolves download path', () async {
    final recording = _RecordingClient();
    final config = WorkerConfig(
      baseUrl: Uri.parse('http://127.0.0.1:8081'),
      modelDownloadSource: WorkerModelDownloadSource.server,
    );
    final api = WorkerApiClient(config: config, httpClient: recording);
    final url = await WorkerModelDownloadResolver.resolveForDownload(
      config: config,
      source: WorkerModelDownloadSource.server,
      api: api,
      accessToken: 'tok',
    );
    expect(recording.lastPath, contains('/artifact-delivery'));
    expect(
      url,
      'http://127.0.0.1:8081/models/${WorkerModelCatalog.modelVersionId}/files/${WorkerModelCatalog.fileName}',
    );
  });
}
