/// Does the radio actually go on for ever?
///
/// **Excluded from the default run** — needs a working connection.
///
/// ```
/// flutter test --tags live test/ytmusic/yt_radio_continuation_live_test.dart
/// ```
///
/// A station that stops after one page is indistinguishable, from inside the
/// app, from a station that ended: `fill` swallows the failure by design,
/// because a batch that will not load is a courtesy the user loses rather than
/// an error worth interrupting them with. That makes this the only place the
/// difference is visible, so it prints what it finds as well as asserting.
@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/services/ytmusic/parse/yt_misc.dart';
import 'package:eq_app/services/ytmusic/yt_innertube.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';
import 'package:eq_app/services/ytmusic/yt_worker.dart';

void main() {
  tearDownAll(YtWorker.instance.dispose);

  /// A song popular enough that YouTube certainly has a station for it.
  const seed = 'kJQP7kiw5Fk';

  test('the first radio page offers a way to ask for more', () async {
    final batch = await YtWorker.instance
        .run<RadioBatch>(YtOp.radio, {'videoId': seed});

    // ignore: avoid_print
    print('[radio] page 1: ${batch.tracks.length} tracks, '
        'continuation ${batch.continuation == null ? "MISSING" : "present"}');
    expect(batch.tracks, isNotEmpty);
    expect(batch.continuation, isNotNull,
        reason: 'without a token the station can never advance past page one, '
            'which is exactly the "radio stops at 9 tracks" symptom');
  });

  test('a continuation returns further tracks, not an empty panel', () async {
    final first = await YtWorker.instance
        .run<RadioBatch>(YtOp.radio, {'videoId': seed});
    final token = first.continuation;
    if (token == null) {
      fail('no continuation on page 1 — the previous test explains why');
    }

    final second = await YtWorker.instance.run<RadioBatch>(
      YtOp.radioContinue,
      {'videoId': seed, 'token': token},
    );

    // ignore: avoid_print
    print('[radio] page 2: ${second.tracks.length} tracks, '
        'continuation ${second.continuation == null ? "MISSING" : "present"}');
    expect(second.tracks, isNotEmpty,
        reason: 'an empty second page is how a station silently ends');

    final firstIds = {for (final t in first.tracks) t.videoId};
    final fresh = second.tracks.where((t) => !firstIds.contains(t.videoId));
    // ignore: avoid_print
    print('[radio] page 2 brought ${fresh.length} tracks page 1 did not');
    expect(fresh, isNotEmpty,
        reason: 'page 2 repeating page 1 means the token was ignored and the '
            'same first page was served again');
  });

  /// The real shape of the promise: keep asking and keep receiving.
  test('the station keeps going for several pages', () async {
    final seen = <String>{};
    String? token;
    var pages = 0;

    for (var i = 0; i < 5; i++) {
      final batch = token == null
          ? await YtWorker.instance.run<RadioBatch>(YtOp.radio, {'videoId': seed})
          : await YtWorker.instance.run<RadioBatch>(
              YtOp.radioContinue, {'videoId': seed, 'token': token});
      if (batch.tracks.isEmpty) break;
      pages++;
      seen.addAll([for (final t in batch.tracks) t.videoId]);
      token = batch.continuation;
      // ignore: avoid_print
      print('[radio] after page $pages: ${seen.length} distinct tracks');
      if (token == null) break;
    }

    expect(pages, greaterThanOrEqualTo(3),
        reason: 'the station stopped after $pages page(s)');
    expect(seen.length, greaterThanOrEqualTo(30),
        reason: 'only ${seen.length} distinct tracks across $pages pages — '
            'an endless station should have produced far more');
  }, timeout: const Timeout(Duration(seconds: 120)));

  /// One seed is not endless, and this measures where it stops.
  ///
  /// Pages converge — each brings fewer tracks the last did not — so a station
  /// pinned to its original seed runs dry at a definite number. Re-seeding from
  /// a track the station itself offered has to get past that, or "endless" is
  /// just a longer finite.
  test('re-seeding gets past what one seed can offer', () async {
    Future<Set<String>> drain(String from, Set<String> seen) async {
      String? token;
      for (var i = 0; i < 6; i++) {
        final batch = token == null
            ? await YtWorker.instance
                .run<RadioBatch>(YtOp.radio, {'videoId': from})
            : await YtWorker.instance.run<RadioBatch>(
                YtOp.radioContinue, {'videoId': from, 'token': token});
        if (batch.tracks.isEmpty) break;
        seen.addAll([for (final t in batch.tracks) t.videoId]);
        token = batch.continuation;
        if (token == null) break;
      }
      return seen;
    }

    final seen = await drain(seed, <String>{});
    final exhausted = seen.length;
    // ignore: avoid_print
    print('[radio] one seed ran to $exhausted distinct tracks');

    // The deepest track this station offered — what the app re-seeds from.
    final deepest = seen.last;
    await drain(deepest, seen);
    // ignore: avoid_print
    print('[radio] after re-seeding from $deepest: ${seen.length} distinct '
        '(+${seen.length - exhausted})');

    expect(seen.length, greaterThan(exhausted),
        reason: 're-seeding produced nothing new, so the station still ends — '
            'the whole point is that one seed running dry is not the end');
  }, timeout: const Timeout(Duration(seconds: 180)));

  /// Where the continuation travels matters.
  ///
  /// `browse` carries a comment earned the hard way: a continuation sent in the
  /// body answers 200 with an empty section list, and only the query-string form
  /// works. `next` sends its continuation in the body. This checks whether that
  /// same trap applies here, and prints both answers either way.
  test('diagnostic: body vs query-string continuation on next', () async {
    final api = YtInnerTube();
    addTearDown(api.close);

    final first = parseRadioPage(await api.next(seed));
    final token = first.continuation;
    // ignore: avoid_print
    print('[diag] page 1 tracks=${first.tracks.length} token=${token != null}');
    if (token == null) return;

    final viaBody = parseRadioPage(await api.next(seed, continuation: token));
    // ignore: avoid_print
    print('[diag] body-form continuation -> ${viaBody.tracks.length} tracks');

    final viaQuery =
        parseRadioPage(await api.nextContinuation(seed, token));
    // ignore: avoid_print
    print('[diag] query-form continuation -> ${viaQuery.tracks.length} tracks');

    expect(viaBody.tracks.length + viaQuery.tracks.length, greaterThan(0),
        reason: 'neither form returned anything — the token or the endpoint '
            'has changed shape');
  }, timeout: const Timeout(Duration(seconds: 120)));
}
