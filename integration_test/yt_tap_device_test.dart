/// What a tap actually waits on, step by step, on the device.
///
/// `YtPlayback.play` awaits three things before the player is shown: the stream
/// resolve, the artwork fetch, and the hand-off to the controller. A spinner
/// that never goes away means one of them never completes — this times each in
/// isolation so the answer is a number, not a guess.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:eq_app/services/ytmusic/parse/yt_json.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';
import 'package:eq_app/services/ytmusic/yt_repository.dart';
import 'package:eq_app/services/ytmusic/yt_worker.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<T> timed<T>(String label, Future<T> future) async {
    final watch = Stopwatch()..start();
    try {
      final value = await future.timeout(const Duration(seconds: 30));
      // ignore: avoid_print
      print('[tap] $label OK in ${watch.elapsedMilliseconds}ms');
      return value;
    } catch (e) {
      // ignore: avoid_print
      print('[tap] $label FAILED after ${watch.elapsedMilliseconds}ms: $e');
      rethrow;
    }
  }

  testWidgets('each step a tap waits on completes', (tester) async {
    final shelves = await timed(
      'search',
      YtWorker.instance.run<List<ExploreShelf>>(
        YtOp.search,
        {'query': 'Burna Boy', 'params': SearchFilter.songs.params},
      ),
    );
    final item = shelves.expand((s) => s.items).firstWhere((i) => i.isPlayable);
    final track = item.asTrack();
    // ignore: avoid_print
    print('[tap] track "${track.title}" thumb=${track.thumbnail}');

    // 1. The stream resolve — what the spinner is nominally waiting for.
    final target = await timed(
      'audioTarget',
      YtMusicRepository.instance.audioTarget(track.videoId),
    );
    expect(target.url, contains('googlevideo.com'));

    // 2. The artwork fetch, which `play()` also awaits before showing the
    //    player. It uses package:http with no timeout of its own.
    await timed('cacheArtwork', _fetchArtwork(track.thumbnail));

    // 3. A second tap on the same track must be instant (cache hit) — if it
    //    isn't, the cache is not being consulted and every tap pays full price.
    final again = await timed(
      'audioTarget (cached)',
      YtMusicRepository.instance.audioTarget(track.videoId),
    );
    expect(again.url, target.url);
    expect(YtMusicRepository.instance.isResolved(track.videoId), isTrue);
  }, timeout: const Timeout(Duration(seconds: 180)));

  testWidgets('prefetching a screenful does not stall', (tester) async {
    final shelves = await YtWorker.instance.run<List<ExploreShelf>>(
      YtOp.search,
      {'query': 'afrobeats', 'params': SearchFilter.songs.params},
    );
    final ids = [
      for (final shelf in shelves)
        for (final item in shelf.items)
          if (item.isPlayable) item.id,
    ];
    expect(ids, isNotEmpty);
    await timed(
      'prefetch batch',
      YtMusicRepository.instance.audioTargets(ids.take(4).toList()),
    );
  }, timeout: const Timeout(Duration(seconds: 180)));
}

/// Mirrors `YtPlayback.cacheArtwork`'s network call exactly.
Future<void> _fetchArtwork(String? url) async {
  if (url == null || url.isEmpty) return;
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(thumbnailAt(url, 512)));
    final response = await request.close();
    await response.drain<void>();
  } finally {
    client.close(force: true);
  }
}
