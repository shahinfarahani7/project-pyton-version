import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'runtime_exceptions.dart';

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
    bool Function()? shouldAbort,
  }) async {
    void checkAbort() {
      if (shouldAbort?.call() ?? false) {
        throw const ModelDownloadPausedException();
      }
    }

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
        checkAbort();
        final offset = await partial.exists() ? await partial.length() : 0;
        onProgress(_percent(offset));
        if (offset > expectedBytes) {
          throw StateError('Partial model is larger than the pinned artifact');
        }
        if (offset == expectedBytes) break;
        log?.call('Model transfer: continuing at $offset/$expectedBytes bytes');
        try {
          await _transfer(
            url,
            partial,
            offset,
            onProgress,
            shouldAbort: shouldAbort,
          );
        } on Object catch (error) {
          if (error is ModelDownloadPausedException ||
              (shouldAbort?.call() ?? false)) {
            throw const ModelDownloadPausedException();
          }
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
          await _sleepUnlessAborted(retryDelay * failures, shouldAbort);
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

  Future<void> _sleepUnlessAborted(
    Duration duration,
    bool Function()? shouldAbort,
  ) async {
    if (duration <= Duration.zero) {
      await Future<void>.delayed(Duration.zero);
      if (shouldAbort?.call() ?? false) {
        throw const ModelDownloadPausedException();
      }
      return;
    }
    const step = Duration(milliseconds: 100);
    var elapsed = Duration.zero;
    while (elapsed < duration) {
      if (shouldAbort?.call() ?? false) {
        throw const ModelDownloadPausedException();
      }
      final remaining = duration - elapsed;
      final slice = remaining < step ? remaining : step;
      await Future<void>.delayed(slice);
      elapsed += slice;
    }
  }

  Future<void> _transfer(
    Uri url,
    File partial,
    int offset,
    void Function(int) onProgress, {
    bool Function()? shouldAbort,
  }) async {
    final client = HttpClient()..autoUncompress = false;
    var clientClosed = false;
    void closeClient() {
      if (clientClosed) return;
      clientClosed = true;
      client.close(force: true);
    }

    StreamIterator<List<int>>? body;
    Timer? abortWatch;
    if (shouldAbort != null) {
      abortWatch = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (clientClosed || !shouldAbort()) return;
        closeClient();
        final active = body;
        if (active != null) {
          unawaited(
            active.cancel().then<void>(
              (_) {},
              onError: (Object _, StackTrace _) {},
            ),
          );
        }
      });
    }
    RandomAccessFile? output;
    try {
      if (shouldAbort?.call() ?? false) {
        throw const ModelDownloadPausedException();
      }
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
      final iterator = StreamIterator<List<int>>(response.timeout(idleTimeout));
      body = iterator;
      while (await iterator.moveNext()) {
        if ((shouldAbort?.call() ?? false) || clientClosed) {
          throw const ModelDownloadPausedException();
        }
        final bytes = iterator.current;
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
    } on ModelDownloadPausedException {
      rethrow;
    } on Object {
      if ((shouldAbort?.call() ?? false) || clientClosed) {
        throw const ModelDownloadPausedException();
      }
      rethrow;
    } finally {
      abortWatch?.cancel();
      final activeBody = body;
      body = null;
      try {
        await activeBody?.cancel();
      } catch (_) {
        // The response is already being torn down.
      }
      try {
        if (output != null) {
          try {
            await output.flush();
          } finally {
            await output.close();
          }
        }
      } finally {
        closeClient();
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
