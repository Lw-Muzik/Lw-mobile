/// Local copies of streamed songs: fetched in ranges with the player's
/// headers (a throttled range is asked again), reused while they last, pruned
/// to the newest few, and stoppable.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/services/stems/stems_model_store.dart';
import 'package:eq_app/services/stems/stems_stream_cache.dart';

void main() {
  late HttpServer server;
  late Directory dir;
  late List<HttpHeaders> requests;
  // How the fake CDN behaves.
  late bool honourRanges;
  late Set<int> stallOnce; // range starts held past the client's timeout once
  late Set<int> refuse; // range starts answered 403
  Completer<void>? holdWhole;
  final body = List<int>.generate(1000000, (i) => (i * 7) % 251);

  setUp(() async {
    requests = [];
    honourRanges = true;
    stallOnce = {};
    refuse = {};
    holdWhole = null;
    dir = await Directory.systemTemp.createTemp('stems_streams_test');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requests.add(req.headers);
      final res = req.response;
      try {
        final range = req.headers.value(HttpHeaders.rangeHeader);
        final m = range == null
            ? null
            : RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range);
        if (honourRanges && m != null) {
          final a = int.parse(m.group(1)!);
          final b = int.parse(m.group(2)!).clamp(0, body.length - 1);
          if (refuse.contains(a)) {
            res.statusCode = 403;
            await res.close();
            return;
          }
          if (stallOnce.remove(a)) {
            await Future<void>.delayed(const Duration(seconds: 2));
          }
          res.statusCode = 206;
          res.headers.set('content-range', 'bytes $a-$b/${body.length}');
          res.contentLength = b - a + 1;
          res.add(body.sublist(a, b + 1));
        } else {
          res.contentLength = body.length;
          res.add(body.sublist(0, 1000));
          await res.flush();
          await holdWhole?.future;
          res.add(body.sublist(1000));
        }
        await res.close();
      } catch (_) {
        // The client hung up (a dropped range): fine.
      }
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  String url(String id, {String mime = 'audio%2Fmp4', bool clen = true}) =>
      'http://127.0.0.1:${server.port}/videoplayback?id=$id&mime=$mime'
      '${clen ? '&clen=${body.length}' : ''}';

  StemsStreamCache cache({int keep = 4}) => StemsStreamCache(
    directory: () async => dir,
    keep: keep,
    chunkBytes: 64 * 1024,
    parallel: 3,
    chunkTimeout: const Duration(milliseconds: 500),
  );

  test('downloads in ranges, each with the player\'s headers', () async {
    final fractions = <double>[];
    final path = await cache().fetch(
      url('a'),
      headers: const {'User-Agent': 'com.google.ios.youtube/20.10.4'},
      onProgress: fractions.add,
    );
    expect(File(path).readAsBytesSync(), body);
    expect(path, endsWith('.m4a'));
    expect(requests, hasLength((body.length / (64 * 1024)).ceil()));
    for (final h in requests) {
      expect(h.value('user-agent'), 'com.google.ios.youtube/20.10.4');
      expect(h.value(HttpHeaders.rangeHeader), startsWith('bytes='));
    }
    expect(fractions.last, 1.0);
    expect(dir.listSync().where((f) => f.path.endsWith('.part')), isEmpty);
  });

  test('finds the length from the first range when the URL has none', () async {
    final path = await cache().fetch(url('a', clen: false));
    expect(File(path).readAsBytesSync(), body);
  });

  test('a throttled range is dropped and asked for again', () async {
    stallOnce = {3 * 64 * 1024};
    final path = await cache().fetch(url('a'));
    expect(File(path).readAsBytesSync(), body);
    final asked = requests
        .where((h) => h.value(HttpHeaders.rangeHeader)!.startsWith('bytes=${3 * 64 * 1024}-'))
        .length;
    expect(asked, 2);
  });

  test('a refused range fails the fetch and leaves nothing behind', () async {
    refuse = {5 * 64 * 1024};
    await expectLater(cache().fetch(url('a')), throwsA(isA<HttpException>()));
    expect(dir.listSync(), isEmpty);
  });

  test('a server that ignores ranges is streamed whole', () async {
    honourRanges = false;
    final fractions = <double>[];
    final path = await cache().fetch(url('a'), onProgress: fractions.add);
    expect(File(path).readAsBytesSync(), body);
    expect(requests, hasLength(1));
    expect(fractions.last, 1.0);
  });

  test('a finished copy is reused without asking again', () async {
    final c = cache();
    final first = await c.fetch(url('a'));
    final asked = requests.length;
    final second = await c.fetch(url('a'));
    expect(second, first);
    expect(requests, hasLength(asked));
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
    honourRanges = false;
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
