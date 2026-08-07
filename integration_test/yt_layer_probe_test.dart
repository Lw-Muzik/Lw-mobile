/// Worker vs repository: which layer stalls?
///
/// The worker path resolved fine in an earlier device run; the repository path
/// hung. They differ only by a cache and an in-flight map, so this runs both
/// against the same track in one go.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:eq_app/services/ytmusic/yt_models.dart';
import 'package:eq_app/services/ytmusic/yt_repository.dart';
import 'package:eq_app/services/ytmusic/yt_worker.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> timed(String label, Future<Object?> Function() run) async {
    final watch = Stopwatch()..start();
    try {
      final value = await run().timeout(const Duration(seconds: 25));
      // ignore: avoid_print
      print('[layer] $label OK ${watch.elapsedMilliseconds}ms -> '
          '${value.runtimeType}');
    } catch (e) {
      // ignore: avoid_print
      print('[layer] $label FAILED ${watch.elapsedMilliseconds}ms: '
          '${e.runtimeType}: $e');
    }
  }

  testWidgets('worker then repository, same track', (tester) async {
    final shelves = await YtWorker.instance.run<List<ExploreShelf>>(
      YtOp.search,
      {'query': 'Burna Boy', 'params': SearchFilter.songs.params},
    );
    final item = shelves.expand((s) => s.items).firstWhere((i) => i.isPlayable);
    // ignore: avoid_print
    print('[layer] track ${item.id}');

    await timed(
      'worker resolveAudio',
      () => YtWorker.instance
          .run<StreamTarget>(YtOp.resolveAudio, {'videoId': item.id}),
    );
    await timed(
      'repository audioTarget',
      () => YtMusicRepository.instance.audioTarget(item.id),
    );
    await timed(
      'repository audioTarget (2nd)',
      () => YtMusicRepository.instance.audioTarget(item.id),
    );
    await timed(
      'repository audioTargets batch',
      () => YtMusicRepository.instance.audioTargets([item.id]),
    );

    // A DIFFERENT track, never asked for before: separates "repeat request is
    // throttled" from "the connection pool is starved".
    final other = shelves
        .expand((s) => s.items)
        .where((i) => i.isPlayable && i.id != item.id)
        .toList();
    await timed(
      'repository audioTarget (fresh id, cold)',
      () => YtMusicRepository.instance.audioTarget(other[0].id),
    );
    await timed(
      'worker resolveAudio (another fresh id)',
      () => YtWorker.instance
          .run<StreamTarget>(YtOp.resolveAudio, {'videoId': other[1].id}),
    );
    // And a repeat of a fresh id through the worker directly.
    await timed(
      'worker resolveAudio (repeat of fresh id)',
      () => YtWorker.instance
          .run<StreamTarget>(YtOp.resolveAudio, {'videoId': other[1].id}),
    );
  }, timeout: const Timeout(Duration(seconds: 240)));
}
