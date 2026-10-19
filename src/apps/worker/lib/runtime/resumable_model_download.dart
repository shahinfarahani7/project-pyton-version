import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// App-owned transfer state, independent of URL, signed redirects and plugin
/// task lifetimes. Only a fully hashed artifact is handed to the installer.
class ResumableModelDownload {
  ResumableModelDownload({
    required this.directory,
    required this.fileName,
    required this.expectedBytes,
    required this.expectedSha256,
    this.completedFile,
    this.maxAttempts = 5,
    this.idleTimeout = const Duration(seconds: 60),
    this.retryDelay = const Duration(seconds: 3),
  });

  final Directory directory;
  final String fileName;
  final int expectedBytes;
  final String expectedSha256;
  final File? completedFile;
  final int maxAttempts;
  final Duration idleTimeout;
  final Duration retryDelay;
  static final Set<String> _active = {};

  Future<File> download({
    required Uri url,
    required void Function(int percent) onProgress,
    void Function(String message)? log,
  }) async {
    if (expectedBytes <= 0 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedSha256) ||
        maxAttempts < 1 ||
        File(fileName).uri.pathSegments.last != fileName) {
      throw ArgumentError(
        'A pinned artifact identity and file name are required',
      );
    }
    final artifactDir = Directory('${directory.path}/$expectedSha256');
    final key = artifactDir.absolute.path;
    if (!_active.add(key)) {
      throw StateError('Model transfer is already in progress');
    }
    try {
      await artifactDir.create(recursive: true);
      final ready = completedFile ?? File('${artifactDir.path}/$fileName');
      final partial = File('${artifactDir.path}/$fileName.part');
      // An interrupted activation can reuse the completed transfer too.
      if (await ready.exists()) {
        await _verify(ready);
        onProgress(100);
        return ready;
      }
      var failures = 0;
      while (true) {
        final offset = await partial.exists() ? await partial.length() : 0;
        onProgress(_percent(offset));
        if (offset > expectedBytes) {
          throw StateError('Partial model is larger than the pinned artifact');
        }
        if (offset == expectedBytes) break;
        log?.call('Model transfer: continuing at $offset/$expectedBytes bytes');
        try {
          await _transfer(url, partial, offset, onProgress);
        } on Object catch (error) {
          final retryable =
              error is SocketException ||
              error is HttpException ||
              error is TimeoutException;
          failures++;
          if (!retryable || failures >= maxAttempts) rethrow;
          log?.call(
            'Model connection interrupted; saved bytes retained. '
            'Retry $failures/${maxAttempts - 1}',
          );
          await Future<void>.delayed(retryDelay * failures);
        }
      }
      if (!await partial.exists() || await partial.length() != expectedBytes) {
        throw const HttpException(
          'Model transfer incomplete; retry to continue',
        );
      }
      await _verify(partial);
      await ready.parent.create(recursive: true);
      final result = await partial.rename(ready.path);
      onProgress(100);
      return result;
    } finally {
      _active.remove(key);
    }
  }

  int _percent(int bytes) => ((bytes * 100) ~/ expectedBytes).clamp(0, 99);

  Future<void> _transfer(
    Uri url,
    File partial,
    int offset,
    void Function(int) onProgress,
  ) async {
    final client = HttpClient()..autoUncompress = false;
    RandomAccessFile? output;
    try {
      client.connectionTimeout = idleTimeout;
      final request = await client.getUrl(url).timeout(idleTimeout);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      }
      final response = await request.close().timeout(idleTimeout);
      final status = response.statusCode;
      if (status == 408 || status == 429 || status >= 500) {
        throw HttpException(
          'Model server temporarily unavailable: HTTP $status',
        );
      }
      if (offset > 0 && status == 200) {
        throw StateError(
          'Server did not accept resume. Saved model bytes kept; '
          'use a download server that supports byte ranges.',
        );
      }
      if (status != 200 && status != 206) {
        throw StateError(
          'Model download rejected: HTTP $status; saved bytes kept',
        );
      }
      final encoding = response.headers.value(
        HttpHeaders.contentEncodingHeader,
      );
      if (encoding != null && encoding != 'identity') {
        throw StateError('Encoded model response cannot be safely resumed');
      }
      var end = expectedBytes - 1;
      if (status == 206) {
        final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(
          response.headers.value(HttpHeaders.contentRangeHeader) ?? '',
        );
        if (range == null ||
            int.parse(range[1]!) != offset ||
            int.parse(range[3]!) != expectedBytes) {
          throw StateError('Invalid model Content-Range; saved bytes kept');
        }
        end = int.parse(range[2]!);
        if (end < offset || end >= expectedBytes) {
          throw StateError('Invalid model range end; saved bytes kept');
        }
      }
      final bodyLength = end - offset + 1;
      if (response.contentLength >= 0 && response.contentLength != bodyLength) {
        throw StateError('Model response size differs from pinned artifact');
      }
      output = await partial.open(mode: FileMode.append);
      var received = offset;
      var lastPercent = _percent(offset);
      await for (final bytes in response.timeout(idleTimeout)) {
        if (received + bytes.length > end + 1) {
          throw StateError('Model response exceeded declared range');
        }
        await output.writeFrom(bytes);
        received += bytes.length;
        final percent = _percent(received);
        if (percent != lastPercent) {
          onProgress(percent);
          lastPercent = percent;
        }
      }
      if (received != end + 1) {
        throw const HttpException(
          'Model connection closed before range completed',
        );
      }
    } finally {
      try {
        if (output != null) {
          try {
            await output.flush();
          } finally {
            await output.close();
          }
        }
      } finally {
        client.close(force: true);
      }
    }
  }

  Future<void> _verify(File file) async {
    final length = await file.length();
    final digest = length == expectedBytes
        ? (await sha256.bind(file.openRead()).first).toString()
        : null;
    if (digest != expectedSha256) {
      // Never activate corrupt bytes or silently splice a changed remote file.
      await file.rename(
        '${file.path}.invalid-${DateTime.now().microsecondsSinceEpoch}',
      );
      throw StateError(
        'Model integrity check failed. Invalid file quarantined; '
        'a fresh download is required.',
      );
    }
  }
}
