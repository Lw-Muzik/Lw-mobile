/// Local copies of streamed songs for live stems: fetched with the player's
/// headers, reused while they last, pruned to the newest few, stoppable, and
/// never left half-written. (The ranged transfer itself is covered by
/// test/ytmusic/yt_stream_fetch_test.dart.)
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/services/stems/stems_model_store.dart';
import 'package:eq_app/services/stems/stems_stream_cache.dart';
import 'package:eq_app/services/ytmusic/yt_stream_fetch.dart';

void main() {
  late HttpServer server;
  late Directory dir;
  late List<HttpHeaders> requests;
  late int status;
  Completer<void>? holdWhole;
  final body = List<int>.generate(300000, (i) => (i * 7) % 251);

  setUp(() async {
    requests = [];
    status = 200;
    holdWhole = null;
    dir = await Directory.systemTemp.createTemp('stems_streams_test');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requests.add(req.headers);
      final res = req.response;
      try {
        final m = RegExp(
          r'bytes=(\d+)-(\d+)',
        ).firstMatch(req.headers.value(HttpHeaders.rangeHeader) ?? '');
        if (status != 200) {
          res.statusCode = status;
        } else if (holdWhole == null && m != null) {
          final a = int.parse(m.group(1)!);
          final b = int.parse(m.group(2)!).clamp(0, body.length - 1);
          res.statusCode = 206;
          res.headers.set('content-range', 'bytes $a-$b/${body.length}');
          res.contentLength = b - a + 1;
          res.add(body.sublist(a, b + 1));
        } else {
          // Ranges ignored: the whole file, held open on request.
          res.contentLength = body.length;
          res.add(body.sublist(0, 1000));
          await res.flush();
          await holdWhole?.future;
          res.add(body.sublist(1000));
        }
        await res.close();
      } catch (_) {}
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  String url(String id, {String mime = 'audio%2Fmp4'}) =>
      'http://127.0.0.1:${server.port}/videoplayback?id=$id&mime=$mime'
      '&clen=${body.length}';

  StemsStreamCache cache({int keep = 4}) => StemsStreamCache(
    directory: () async => dir,
    keep: keep,
    fetcher: const YtStreamFetch(
      chunkBytes: 64 * 1024,
      chunkTimeout: Duration(milliseconds: 500),
    ),
  );

  test('fetches the stream with its headers, reporting progress', () async {
    final fractions = <double>[];
    final path = await cache().fetch(
      url('a'),
      headers: const {'User-Agent': 'com.google.ios.youtube/20.10.4'},
      onProgress: fractions.add,
    );
    expect(File(path).readAsBytesSync(), body);
    expect(path, endsWith('.m4a'));
    expect(
      requests.map((h) => h.value('user-agent')).toSet(),
      {'com.google.ios.youtube/20.10.4'},
    );
    expect(fractions.last, 1.0);
    expect(dir.listSync().where((f) => f.path.endsWith('.part')), isEmpty);
  });

  test('a finished copy is reused without asking again', () async {
    final c = cache();
    final first = await c.fetch(url('a'));
    final asked = requests.length;
    final second = await c.fetch(url('a'));
    expect(second, first);
    expect(requests, hasLength(asked));
  });

  test('two asks for one stream share a transfer', () async {
    final c = cache();
    final both = await Future.wait([c.fetch(url('a')), c.fetch(url('a'))]);
    expect(both[0], both[1]);
    expect(requests, hasLength((body.length / (64 * 1024)).ceil()));
  });

  test('a refused stream fails and leaves nothing behind', () async {
    status = 403;
    await expectLater(cache().fetch(url('a')), throwsA(isA<HttpException>()));
    expect(dir.listSync(), isEmpty);
  });

  test('only the newest copies stay', () async {
    final c = cache(keep: 2);
    for (final id in ['a', 'b', 'c']) {
      await c.fetch(url(id));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final names = dir.listSync().map((f) => f.uri.pathSegments.last).toSet();
    expect(names, {
      StemsStreamCache.fileNameFor(url('b')),
      StemsStreamCache.fileNameFor(url('c')),
    });
  });

  test('cancelling stops the transfer and keeps no partial file', () async {
    holdWhole = Completer<void>();
    final token = StemsCancelToken();
    final fetch = cache().fetch(url('a'), cancel: token);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    token.cancel();
    await expectLater(fetch, throwsA(isA<StemsDownloadCancelled>()));
    holdWhole!.complete();
    expect(dir.listSync(), isEmpty);
  });

  test('names follow the stream type', () {
    expect(StemsStreamCache.fileNameFor(url('a')), endsWith('.m4a'));
    expect(
      StemsStreamCache.fileNameFor(url('a', mime: 'audio%2Fwebm')),
      endsWith('.webm'),
    );
    expect(
      StemsStreamCache.fileNameFor(url('a')),
      isNot(StemsStreamCache.fileNameFor(url('b'))),
    );
  });
}
