import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../lib/runtime/resumable_model_download.dart';

void main() {
  final bytes = List<int>.generate(32768, (i) => i % 251);
  final digest = sha256.convert(bytes).toString();
  late Directory directory;
  late List<String?> ranges;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('model-resume-test-');
    ranges = [];
  });
  tearDown(() async => directory.delete(recursive: true));

  File partial() => File('${directory.path}/$digest/model.litertlm.part');

  ResumableModelDownload downloader({int attempts = 1}) =>
      ResumableModelDownload(
        directory: directory,
        fileName: 'model.litertlm',
        expectedBytes: bytes.length,
        expectedSha256: digest,
        maxAttempts: attempts,
        retryDelay: Duration.zero,
      );

  Future<Uri> serve(Future<void> Function(HttpRequest) handler) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      ranges.add(request.headers.value(HttpHeaders.rangeHeader));
      await handler(request);
    });
    return Uri.parse('http://127.0.0.1:${server.port}/model');
  }

  Future<void> healthy(HttpRequest request) async {
    final range = request.headers.value(HttpHeaders.rangeHeader);
    final start = range == null
        ? 0
        : int.parse(range.substring(6).split('-').first);
    request.response.statusCode = range == null ? 200 : 206;
    request.response.headers.set('ETag', 'W/"weak-hf-style-tag"');
    if (range != null) {
      request.response.headers.set(
        'Content-Range',
        'bytes $start-${bytes.length - 1}/${bytes.length}',
      );
    }
    request.response.contentLength = bytes.length - start;
    request.response.add(bytes.sublist(start));
    await request.response.close();
  }

  Future<void> cutConnection(HttpRequest request) async {
    final socket = await request.response.detachSocket(writeHeaders: false);
    socket.add(
      ascii.encode(
        'HTTP/1.1 200 OK\r\nContent-Length: ${bytes.length}\r\n'
        'Connection: close\r\n\r\n',
      ),
    );
    socket.add(bytes.sublist(0, 8192));
    await socket.flush();
    await socket.close();
  }

  Future<void> seed(List<int> value) async {
    await partial().parent.create(recursive: true);
    await partial().writeAsBytes(value, flush: true);
  }

  test(
    'fresh download verifies exact bytes and reuses ready file without network',
    () async {
      final url = await serve(healthy);
      final progress = <int>[];
      final file = await downloader().download(
        url: url,
        onProgress: progress.add,
      );
      expect(await file.readAsBytes(), bytes);
      expect(progress.first, 0);
      expect(progress.last, 100);
      await downloader().download(url: url, onProgress: (_) {});
      expect(ranges, [null]);
      expect(await partial().exists(), isFalse);
    },
  );

  test(
    'connection cut preserves bytes; new downloader resumes after app restart',
    () async {
      final broken = await serve(cutConnection);
      await expectLater(
        downloader().download(url: broken, onProgress: (_) {}),
        throwsA(isA<HttpException>()),
      );
      final saved = await partial().length();
      expect(saved, 8192);
      final restoredUrl = await serve(healthy);
      final progress = <int>[];
      final result = await downloader().download(
        url: restoredUrl,
        onProgress: progress.add,
      );
      expect(ranges, [null, 'bytes=$saved-']);
      expect(progress.first, 25);
      expect(await result.readAsBytes(), bytes);
    },
  );

  test(
    'automatic retry requests only remaining bytes, including weak ETag server',
    () async {
      var requests = 0;
      final url = await serve(
        (request) =>
            ++requests == 1 ? cutConnection(request) : healthy(request),
      );
      final result = await downloader(
        attempts: 2,
      ).download(url: url, onProgress: (_) {});
      expect(ranges, [null, 'bytes=8192-']);
      expect(await result.readAsBytes(), bytes);
    },
  );

  test(
    'server ignores Range: retain partial and do not silently start over',
    () async {
      await seed(bytes.sublist(0, 8192));
      final url = await serve((request) async {
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      });
      await expectLater(
        downloader().download(url: url, onProgress: (_) {}),
        throwsStateError,
      );
      expect(await partial().readAsBytes(), bytes.sublist(0, 8192));
      expect(ranges, ['bytes=8192-']);
    },
  );

  for (final contentRange in [
    'bytes 0-32767/32768',
    'bytes 8192-32767/99999',
    'garbage',
  ]) {
    test('reject mismatched range $contentRange before appending', () async {
      await seed(bytes.sublist(0, 8192));
      final url = await serve((request) async {
        request.response.statusCode = 206;
        request.response.headers.set('Content-Range', contentRange);
        request.response.add(bytes.sublist(8192));
        await request.response.close();
      });
      await expectLater(
        downloader().download(url: url, onProgress: (_) {}),
        throwsStateError,
      );
      expect(await partial().length(), 8192);
    });
  }

  test(
    'complete partial from process death is verified and promoted without request',
    () async {
      await seed(bytes);
      final url = await serve(healthy);
      final result = await downloader().download(url: url, onProgress: (_) {});
      expect(await result.readAsBytes(), bytes);
      expect(ranges, isEmpty);
    },
  );

  test('corrupt complete bytes are quarantined and never activated', () async {
    await seed(List<int>.filled(bytes.length, 0));
    final url = await serve(healthy);
    await expectLater(
      downloader().download(url: url, onProgress: (_) {}),
      throwsStateError,
    );
    expect(await partial().exists(), isFalse);
    expect(
      await File('${partial().parent.path}/model.litertlm').exists(),
      isFalse,
    );
    expect(await partial().parent.list().length, 1);
    expect(ranges, isEmpty);
  });

  test('403 retains partial and does not loop or restart', () async {
    await seed(bytes.sublist(0, 8192));
    final url = await serve((request) async {
      request.response.statusCode = 403;
      await request.response.close();
    });
    await expectLater(
      downloader(attempts: 3).download(url: url, onProgress: (_) {}),
      throwsStateError,
    );
    expect(await partial().length(), 8192);
    expect(ranges, ['bytes=8192-']);
  });

  test('transient 503 retries with same saved offset', () async {
    await seed(bytes.sublist(0, 8192));
    var count = 0;
    final url = await serve((request) async {
      if (++count == 1) {
        request.response.statusCode = 503;
        await request.response.close();
      } else {
        await healthy(request);
      }
    });
    await downloader(attempts: 2).download(url: url, onProgress: (_) {});
    expect(ranges, ['bytes=8192-', 'bytes=8192-']);
  });

  test('wrong Content-Length does not overwrite saved bytes', () async {
    await seed(bytes.sublist(0, 8192));
    final url = await serve((request) async {
      request.response.statusCode = 206;
      request.response.headers.set('Content-Range', 'bytes 8192-32767/32768');
      request.response.contentLength = 1;
      request.response.add([42]);
      await request.response.close();
    });
    await expectLater(
      downloader().download(url: url, onProgress: (_) {}),
      throwsStateError,
    );
    expect(await partial().length(), 8192);
  });

  test(
    'completed artifact is promoted to canonical installer path without copying',
    () async {
      final canonical = File('${directory.path}/installed/model.litertlm');
      final url = await serve(healthy);
      final transfer = ResumableModelDownload(
        directory: directory,
        fileName: 'model.litertlm',
        completedFile: canonical,
        expectedBytes: bytes.length,
        expectedSha256: digest,
      );
      final result = await transfer.download(url: url, onProgress: (_) {});
      expect(result.path, canonical.path);
      expect(await result.readAsBytes(), bytes);
      await transfer.download(url: url, onProgress: (_) {});
      expect(ranges, [null]);
      expect(await partial().exists(), isFalse);
    },
  );

  test(
    'server can return multiple smaller valid ranges without using retry budget',
    () async {
      final url = await serve((request) async {
        final range = request.headers.value(HttpHeaders.rangeHeader);
        final start = range == null
            ? 0
            : int.parse(range.substring(6).split('-').first);
        final end = (start + 4095).clamp(0, bytes.length - 1);
        request.response.statusCode = 206;
        request.response.headers.set(
          'Content-Range',
          'bytes $start-$end/${bytes.length}',
        );
        request.response.contentLength = end - start + 1;
        request.response.add(bytes.sublist(start, end + 1));
        await request.response.close();
      });
      final result = await downloader().download(url: url, onProgress: (_) {});
      expect(ranges.length, 8);
      expect(await result.readAsBytes(), bytes);
    },
  );

  test(
    'idle connection times out; next call continues from flushed bytes',
    () async {
      final url = await serve((request) async {
        final socket = await request.response.detachSocket(writeHeaders: false);
        addTearDown(socket.destroy);
        socket.add(ascii.encode('HTTP/1.1 200 OK\r\nContent-Length: ${bytes.length}\r\n'
            'Connection: close\r\n\r\n'));
        socket.add(bytes.sublist(0, 8192));
        await socket.flush();
      });
      final transfer = ResumableModelDownload(
        directory: directory,
        fileName: 'model.litertlm',
        expectedBytes: bytes.length,
        expectedSha256: digest,
        maxAttempts: 1,
        idleTimeout: const Duration(milliseconds: 200),
      );
      await expectLater(
        transfer.download(url: url, onProgress: (_) {}),
        throwsA(isA<Exception>()),
      );
      expect(await partial().length(), 8192);
      final restored = await serve(healthy);
      final file = await downloader().download(
        url: restored,
        onProgress: (_) {},
      );
      expect(await file.readAsBytes(), bytes);
      expect(ranges.last, 'bytes=8192-');
    },
  );
}
