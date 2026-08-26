/// Does the resolved stream serve the *whole file*, not just its first slice?
///
/// This is the test whose absence let a broken build pass. Every earlier probe
/// read `bytes=0-65535` and reported success — but an IOS-resolved url is
/// **PO-token gated to roughly its first 1 MiB**, so a 64 KB read proves only
/// that the first 64 KB exist. About 64 seconds into the track, every request
/// 403s and the player stops.
///
/// So: always read past the wall.
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:eq_app/services/ytmusic/yt_innertube.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';
import 'package:eq_app/services/ytmusic/yt_worker.dart';

const _mib = 1024 * 1024;

void main() {
  tearDownAll(YtWorker.instance.dispose);

  Future<StreamTarget> resolve() async {
    final shelves = await YtWorker.instance.run<List<ExploreShelf>>(
      YtOp.search,
      {'query': 'Burna Boy Last Last', 'params': SearchFilter.songs.params},
    );
    final song = shelves.expand((s) => s.items).firstWhere((i) => i.isPlayable);
    return YtWorker.instance
        .run<StreamTarget>(YtOp.resolveAudio, {'videoId': song.id});
  }

  Future<int> status(String url, String range) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.rangeHeader, range);
      YtInnerTube.audioPlaybackHeaders.forEach(request.headers.set);
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      client.close(force: true);
    }
  }

  test('the resolver learns a visitorData', () async {
    await resolve();
    // Not asserted on the instance (it lives in the worker isolate) — the proof
    // is that resolution succeeds at all, which without one it does not.
  }, timeout: const Timeout(Duration(seconds: 60)));

  /// The whole point. A url that only serves its first megabyte plays for about
  /// a minute and then dies, which reads to a user as "it stopped".
  test('the resolved url serves bytes PAST the 1 MiB gate', () async {
    final target = await resolve();

    expect(await status(target.url, 'bytes=0-${_mib - 1}'), anyOf(200, 206),
        reason: 'the first megabyte is served by gated urls too');

    // Everything below is what a gated url refuses.
    expect(await status(target.url, 'bytes=$_mib-${2 * _mib - 1}'),
        anyOf(200, 206),
        reason: 'the chunk after the gate — 403 here means a gated (IOS) url '
            'and about 64 seconds of playback before silence');

    expect(await status(target.url, 'bytes=${2 * _mib}-${2 * _mib + 65535}'),
        anyOf(200, 206),
        reason: 'a mid-file seek must work, not just sequential reads');
  }, timeout: const Timeout(Duration(seconds: 90)));

  /// The exact request ExoPlayer makes on first open, and the one this suite
  /// used to look at and decline to judge.
  ///
  /// The old comment here said a chunking proxy stood between the player and
  /// the CDN, so an open-ended refusal did not matter. There is no such proxy:
  /// `AudioHandler` builds its players with `useProxyForRequestHeaders: false`
  /// precisely so ExoPlayer talks to googlevideo directly. The player's first
  /// act is one `Range: bytes=0-` for the whole file, and on 2026-08-14 that
  /// request was being answered 403 for every IOS-resolved url — which is why
  /// tapping a search result opened the player and played nothing at all.
  ///
  /// Nor would a proxy have saved it: the gate is on the *offset*, not the
  /// request shape. Walked in bounded 512 KiB chunks, a gated url serves
  /// exactly 1048576 bytes and then 403s. There is no way to play a gated url;
  /// there is only not being handed one.
  test('an open-ended range — what ExoPlayer actually sends — is served',
      () async {
    final target = await resolve();

    expect(await status(target.url, 'bytes=0-'), anyOf(200, 206),
        reason: 'the whole-file request every player opens with. A 403 here '
            'is a track that plays nothing, however well it probes in slices');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
