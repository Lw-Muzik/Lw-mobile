/// Fetching a YouTube stream in ranges against a fake googlevideo: the whole
/// file lands intact however the ranges finish, a throttled or cut range is
/// asked for again, a refusal is final, a server that ignores ranges is
/// streamed, and a cancel stops it.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/services/ytmusic/yt_stream_fetch.dart';

void main() {
  late HttpServer server;
  late Directory dir;
  late List<HttpHeaders> requests;
  // How the fake CDN behaves.
  late bool honourRanges;
  late Set<int> stallOnce; // range starts held past the client's timeout once
  late Set<int> cutOnce; // range starts cut off halfway once
  late Set<int> refuse; // range starts answered 403
  late Duration everyRange; // a slow link: each range takes this long
  Completer<void>? holdWhole;
  final body = List<int>.generate(1000000, (i) => (i * 7) % 251);
  const chunk = 64 * 1024;

  setUp(() async {
    requests = [];
    honourRanges = true;
    stallOnce = {};
    cutOnce = {};
    refuse = {};
    everyRange = Duration.zero;
    holdWhole = null;
    dir = await Directory.systemTemp.createTemp('yt_stream_fetch_test');
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
          await Future<void>.delayed(everyRange);
          res.statusCode = 206;
          res.headers.set('content-range', 'bytes $a-$b/${body.length}');
          res.contentLength = b - a + 1;
          if (cutOnce.remove(a)) {
            res.add(body.sublist(a, a + (b - a + 1) ~/ 2));
            await res.flush();
            (await res.detachSocket(writeHeaders: false)).destroy();
            return;
          }
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

  Uri url({bool clen = true}) => Uri.parse(
    'http://127.0.0.1:${server.port}/videoplayback?id=a&mime=audio%2Fmp4'
    '${clen ? '&clen=${body.length}' : ''}',
  );

  const fetch = YtStreamFetch(
    chunkBytes: chunk,
    parallel: 3,
    chunkTimeout: Duration(milliseconds: 500),
  );
  File out() => File('${dir.path}/song.part');

  test('fetches the whole stream in ranges, each with the headers', () async {
    final fractions = <double>[];
    await fetch.toFile(
      url(),
      out(),
      headers: const {'User-Agent': 'com.google.ios.youtube/20.10.4'},
      onProgress: fractions.add,
    );
    expect(out().readAsBytesSync(), body);
    expect(requests, hasLength((body.length / chunk).ceil()));
    for (final h in requests) {
      expect(h.value('user-agent'), 'com.google.ios.youtube/20.10.4');
      expect(h.value(HttpHeaders.rangeHeader), startsWith('bytes='));
    }
    expect(fractions.last, 1.0);
    for (var i = 1; i < fractions.length; i++) {
      expect(fractions[i], greaterThanOrEqualTo(fractions[i - 1]));
    }
  });

  test('finds the length from the first range when the URL has none', () async {
    await fetch.toFile(url(clen: false), out());
    expect(out().readAsBytesSync(), body);
  });

  test('a throttled range is dropped and asked for again', () async {
    stallOnce = {3 * chunk};
    await fetch.toFile(url(), out());
    expect(out().readAsBytesSync(), body);
    expect(_askedFor(requests, 3 * chunk), 2);
  });

  test('a slow network is not mistaken for throttling', () async {
    // Every range takes 250 ms against a 50 ms floor: once one has been
    // timed, the bar is four times the median, and nothing is asked twice.
    // (The first range has no measure yet; its last try has no limit.)
    everyRange = const Duration(milliseconds: 250);
    const slowFloor = YtStreamFetch(
      chunkBytes: chunk,
      parallel: 3,
      chunkTimeout: Duration(milliseconds: 50),
    );
    await slowFloor.toFile(url(), out());
    expect(out().readAsBytesSync(), body);
    for (var start = chunk; start < body.length; start += chunk) {
      expect(_askedFor(requests, start), 1, reason: 'range at $start');
    }
  });

  test('a range cut off halfway is asked for again', () async {
    cutOnce = {7 * chunk};
    await fetch.toFile(url(), out());
    expect(out().readAsBytesSync(), body);
    expect(_askedFor(requests, 7 * chunk), 2);
  });

  test('a refused range fails the fetch, with its status', () async {
    refuse = {5 * chunk};
    await expectLater(
      fetch.toFile(url(), out()),
      throwsA(isA<YtStreamRefused>().having((e) => e.statusCode, 'status', 403)),
    );
    expect(_askedFor(requests, 5 * chunk), 1, reason: 'a refusal is final');
  });

  test('a refused first request fails at once', () async {
    refuse = {0};
    await expectLater(
      fetch.toFile(url(), out()),
      throwsA(isA<YtStreamRefused>()),
    );
    expect(requests, hasLength(1));
  });

  test('a server that ignores ranges is streamed whole', () async {
    honourRanges = false;
    final fractions = <double>[];
    await fetch.toFile(url(), out(), onProgress: fractions.add);
    expect(out().readAsBytesSync(), body);
    expect(requests, hasLength(1));
    expect(fractions.last, 1.0);
  });

  test('cancelling stops the transfer', () async {
    honourRanges = false;
    holdWhole = Completer<void>();
    final cancel = Completer<void>();
    final run = fetch.toFile(url(), out(), cancel: cancel.future);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    cancel.complete();
    await expectLater(run, throwsA(isA<YtStreamFetchCancelled>()));
    holdWhole!.complete();
  });
}

int _askedFor(List<HttpHeaders> requests, int start) => requests
    .where((h) => h.value(HttpHeaders.rangeHeader)!.startsWith('bytes=$start-'))
    .length;
