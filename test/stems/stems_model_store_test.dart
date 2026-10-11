/// The model download: nothing gets the name the native loader opens unless
/// its size and SHA-256 match the manifest, a bad host is abandoned for the
/// next one, and an interrupted download resumes without trusting anything
/// half-written.
///
/// A real server is replaced by `MockClient.streaming`, so a test can serve a
/// wrong body, a lying Content-Length, a stalled stream, or look at the disk
/// in the middle of a transfer.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:eq_app/services/stems/stems_manifest.dart';
import 'package:eq_app/services/stems/stems_model_store.dart';

const _primary = 'https://primary.test/models';
const _fallback = 'https://fallback.test/models';

List<int> _bytes(int length, int seed) =>
    List<int>.generate(length, (i) => (i * 31 + seed * 7 + (i >> 8)) & 0xff);

StemsModelManifest _manifestFor(Map<String, List<int>> files) =>
    StemsModelManifest(
      id: 'test-model',
      version: 3,
      totalBytes: files.values.fold(0, (sum, b) => sum + b.length),
      files: [
        for (final entry in files.entries)
          StemsModelFile(
            name: entry.key,
            size: entry.value.length,
            sha256: sha256.convert(entry.value).toString(),
            urls: ['$_primary/${entry.key}', '$_fallback/${entry.key}'],
          ),
      ],
    );

Stream<List<int>> _chunked(List<int> bytes, {int size = 4096}) async* {
  for (var i = 0; i < bytes.length; i += size) {
    yield bytes.sublist(i, math.min(i + size, bytes.length));
  }
}

typedef _Route = Future<http.StreamedResponse> Function(http.BaseRequest);

/// Serves [files] by name from both hosts, unless a route says otherwise.
class _FakeServer {
  _FakeServer(this.files);

  final Map<String, List<int>> files;
  final List<String> requests = [];
  final Map<String, _Route> routes = {};

  http.Client client() => MockClient.streaming((request, _) async {
    final url = request.url.toString();
    requests.add(url);
    final route = routes[url];
    if (route != null) return route(request);
    final bytes = files[request.url.pathSegments.last];
    if (bytes == null) {
      return http.StreamedResponse(const Stream.empty(), 404);
    }
    return http.StreamedResponse(
      _chunked(bytes),
      200,
      contentLength: bytes.length,
    );
  });
}

void main() {
  late Directory base;
  final vocals = _bytes(20000, 1);
  final drums = _bytes(16384 + 7, 2);
  late Map<String, List<int>> files;
  late StemsModelManifest manifest;
  late _FakeServer server;

  StemsModelStore store({Duration idle = const Duration(seconds: 5)}) =>
      StemsModelStore(
        manifest: manifest,
        clientFactory: server.client,
        baseDirectory: () async => base,
        idleTimeout: idle,
      );

  Directory modelDir() => Directory('${base.path}/stems/test-model-v3');
  File inModel(String name) => File('${modelDir().path}/$name');

  setUp(() async {
    base = await Directory.systemTemp.createTemp('stems_store_test');
    files = {'vocals.onnx': vocals, 'drums.onnx': drums};
    manifest = _manifestFor(files);
    server = _FakeServer(files);
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  test('downloads, verifies and marks the model ready', () async {
    final progress = <int>[];
    final phases = <StemsDownloadPhase>[];
    final s = store();
    expect(await s.isReady(), isFalse);

    await s.download(
      onProgress: (p) => progress.add(p.receivedBytes),
      onPhase: phases.add,
    );

    expect(await inModel('vocals.onnx').readAsBytes(), vocals);
    expect(await inModel('drums.onnx').readAsBytes(), drums);
    expect(await s.isReady(), isTrue);
    final marker = jsonDecode(
      await inModel(StemsModelStore.markerName).readAsString(),
    ) as Map;
    expect(marker['id'], 'test-model');
    expect(marker['version'], 3);
    expect(
      modelDir().listSync().where((e) => e.path.endsWith('.part')),
      isEmpty,
    );
    expect(progress.last, manifest.totalBytes);
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }
    expect(phases, [
      StemsDownloadPhase.checking,
      StemsDownloadPhase.downloading,
    ]);
    expect(server.requests, ['$_primary/vocals.onnx', '$_primary/drums.onnx']);
  });

  test(
    'a host answering with the wrong length is dropped at the headers',
    () async {
      // What a web server's catch-all page looks like: 200, text/html, 54 KB.
      server.routes['$_primary/vocals.onnx'] = (_) async =>
          http.StreamedResponse(
            Stream.value(utf8.encode('<!doctype html><title>Hype</title>')),
            200,
            contentLength: 54639,
            headers: {'content-type': 'text/html'},
          );
      final bytesBeforeFallback = <int>[];

      await store().download(
        onProgress: (p) {
          if (server.requests.length < 2) {
            bytesBeforeFallback.add(p.receivedBytes);
          }
        },
      );

      expect(
        bytesBeforeFallback.where((b) => b > 0),
        isEmpty,
        reason: 'not a byte of the HTML page is written',
      );
      expect(server.requests.take(2), [
        '$_primary/vocals.onnx',
        '$_fallback/vocals.onnx',
      ]);
      expect(await inModel('vocals.onnx').readAsBytes(), vocals);
    },
  );

  test('a host that errors falls through to the next one', () async {
    server.routes['$_primary/drums.onnx'] = (_) async =>
        http.StreamedResponse(const Stream.empty(), 503);

    await store().download();

    expect(server.requests, contains('$_fallback/drums.onnx'));
    expect(await store().isReady(), isTrue);
  });

  test(
    'a body of the right size but the wrong bytes is never renamed',
    () async {
      final forged = List<int>.from(drums)..[100] ^= 0xff;
      for (final host in [_primary, _fallback]) {
        server.routes['$host/drums.onnx'] = (_) async => http.StreamedResponse(
          _chunked(forged),
          200,
          contentLength: forged.length,
        );
      }

      final s = store();
      await expectLater(s.download(), throwsA(isA<StemsDownloadException>()));

      expect(inModel('drums.onnx').existsSync(), isFalse);
      expect(
        inModel('drums.onnx${StemsModelStore.partSuffix}').existsSync(),
        isFalse,
      );
      expect(inModel(StemsModelStore.markerName).existsSync(), isFalse);
      expect(await s.isReady(), isFalse);
      // The file that did verify is kept for the next attempt.
      expect(await inModel('vocals.onnx').readAsBytes(), vocals);
    },
  );

  test('a short body without a Content-Length fails its size check', () async {
    for (final host in [_primary, _fallback]) {
      server.routes['$host/vocals.onnx'] = (_) async =>
          http.StreamedResponse(_chunked(vocals.sublist(0, 1000)), 200);
    }

    await expectLater(
      store().download(),
      throwsA(
        isA<StemsDownloadException>().having(
          (e) => e.message,
          'message',
          contains("didn't check out"),
        ),
      ),
    );
    expect(inModel('vocals.onnx').existsSync(), isFalse);
  });

  test('the bytes sit under a temporary name until they verify', () async {
    final gate = Completer<void>();
    final body = StreamController<List<int>>();
    server.routes['$_primary/drums.onnx'] = (_) async {
      body.add(drums.sublist(0, 4096));
      unawaited(
        gate.future.then((_) async {
          body.add(drums.sublist(4096));
          await body.close();
        }),
      );
      return http.StreamedResponse(
        body.stream,
        200,
        contentLength: drums.length,
      );
    };

    final download = store().download(
      onProgress: (p) {
        // First chunk of drums written: look at the disk mid-transfer.
        if (!gate.isCompleted && p.receivedBytes == vocals.length + 4096) {
          expect(inModel('drums.onnx').existsSync(), isFalse);
          expect(
            inModel('drums.onnx${StemsModelStore.partSuffix}').existsSync(),
            isTrue,
          );
          gate.complete();
        }
      },
    );
    await download;

    expect(gate.isCompleted, isTrue);
    expect(await inModel('drums.onnx').readAsBytes(), drums);
  });

  test(
    'resumes: verified files are kept, damaged ones are fetched again',
    () async {
      await modelDir().create(recursive: true);
      await inModel('vocals.onnx').writeAsBytes(vocals);
      // Right size, wrong bytes: a file written by something else, or damaged.
      await inModel('drums.onnx')
          .writeAsBytes(List<int>.filled(drums.length, 0));

      await store().download();

      expect(server.requests, ['$_primary/drums.onnx']);
      expect(await inModel('drums.onnx').readAsBytes(), drums);
      expect(await store().isReady(), isTrue);
    },
  );

  test('a ready model is not downloaded again', () async {
    await store().download();
    server.requests.clear();

    final progress = <StemsDownloadProgress>[];
    await store().download(onProgress: progress.add);

    expect(server.requests, isEmpty);
    expect(progress.single.receivedBytes, manifest.totalBytes);
  });

  test('cancel stops mid-transfer and leaves nothing half-written', () async {
    final token = StemsCancelToken();
    final body = StreamController<List<int>>();
    var cancelledUpstream = false;
    body.onCancel = () => cancelledUpstream = true;
    server.routes['$_primary/vocals.onnx'] = (_) async {
      body.add(vocals.sublist(0, 4096));
      return http.StreamedResponse(
        body.stream,
        200,
        contentLength: vocals.length,
      );
    };

    final download = store().download(
      cancel: token,
      onProgress: (p) {
        if (p.receivedBytes > 0) token.cancel();
      },
    );

    await expectLater(download, throwsA(isA<StemsDownloadCancelled>()));
    expect(cancelledUpstream, isTrue);
    expect(inModel('vocals.onnx').existsSync(), isFalse);
    expect(
      inModel('vocals.onnx${StemsModelStore.partSuffix}').existsSync(),
      isFalse,
    );
    expect(await store().isReady(), isFalse);
    expect(
      server.requests,
      isNot(contains('$_fallback/vocals.onnx')),
      reason: 'a cancel is not a failure to fall back from',
    );
  });

  test('a stalled transfer times out and moves to the next host', () async {
    server.routes['$_primary/vocals.onnx'] = (_) async => http.StreamedResponse(
      StreamController<List<int>>().stream, // never sends a byte
      200,
      contentLength: vocals.length,
    );

    await store(idle: const Duration(milliseconds: 150)).download();

    expect(server.requests, contains('$_fallback/vocals.onnx'));
    expect(await inModel('vocals.onnx').readAsBytes(), vocals);
  });

  group('isReady', () {
    test('wants every file at its exact size', () async {
      await store().download();
      await inModel('drums.onnx').writeAsBytes([1, 2, 3]);
      expect(await store().isReady(), isFalse);
    });

    test('wants every file present', () async {
      await store().download();
      await inModel('vocals.onnx').delete();
      expect(await store().isReady(), isFalse);
    });

    test('wants a marker for this model version', () async {
      await store().download();
      await inModel(StemsModelStore.markerName)
          .writeAsString(jsonEncode({'id': 'test-model', 'version': 2}));
      expect(await store().isReady(), isFalse);
    });
  });

  test('delete removes the model directory', () async {
    final s = store();
    await s.download();
    await s.delete();
    expect(modelDir().existsSync(), isFalse);
    expect(await s.isReady(), isFalse);
  });

  group('the embedded manifest', () {
    const real = StemsModelManifest.spleeter4StemsFp16;

    test('adds up', () {
      expect(
        real.files.fold<int>(0, (sum, f) => sum + f.size),
        real.totalBytes,
      );
      expect(real.directoryName, 'spleeter-4stems-fp16-v1');
      expect(real.files.map((f) => f.name), [
        'vocals.onnx',
        'drums.onnx',
        'bass.onnx',
        'other.onnx',
      ]);
    });

    test('tries our host first, then Hugging Face', () {
      for (final f in real.files) {
        final stem = f.name.replaceAll('.onnx', '');
        expect(f.urls, [
          'https://hypemuzik.com/models/stems/spleeter-4stems-fp16-v1/${f.name}',
          'https://huggingface.co/Best-Practice/spleeter-4stems-onnx/resolve/main/$stem.fp16.onnx',
        ]);
        expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      }
    });
  });
}
