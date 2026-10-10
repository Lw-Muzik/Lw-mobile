import 'dart:async';

import 'package:eq_app/player/queue_sync.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in for the gapless player: a source list that a load replaces
/// wholesale with a snapshot of the model, and appends extend.
class FakePlayer {
  final List<String> sources = [];

  /// Starts a load the way `loadGaplessQueue` does: the snapshot is taken
  /// now, the list is replaced when the load completes.
  Future<void> load(List<String> model, Completer<void> gate) async {
    final snapshot = [...model];
    await gate.future;
    sources
      ..clear()
      ..addAll(snapshot);
  }
}

void main() {
  test('an append during a gapless load survives it (the one-song mix)', () async {
    final model = ['first'];
    final player = FakePlayer()..sources.addAll(['old a', 'old b']);
    final sync = PlayerQueueSync();

    final gate = Completer<void>();
    final load = player.load(model, gate);

    // The mix's other tracks resolve instantly and are appended mid-load.
    model.addAll([for (var i = 2; i <= 25; i++) 'track $i']);
    final append = sync.serial(() => PlayerQueueSync.catchUp(
          pendingLoad: load,
          playerLength: () => player.sources.length,
          modelLength: () => model.length,
          addFrom: (from) async => player.sources.addAll(model.sublist(from)),
        ));

    gate.complete();
    await append;
    expect(player.sources, model, reason: 'all 25 tracks reach the player');
  });

  test('concurrent appends never duplicate tracks', () async {
    final model = ['a'];
    final player = FakePlayer()..sources.add('a');
    final sync = PlayerQueueSync();

    Future<void> append(List<String> extra) {
      model.addAll(extra);
      return sync.serial(() => PlayerQueueSync.catchUp(
            pendingLoad: null,
            playerLength: () => player.sources.length,
            modelLength: () => model.length,
            addFrom: (from) async {
              await Future<void>.delayed(const Duration(milliseconds: 5));
              player.sources.addAll(model.sublist(from));
            },
          ));
    }

    await Future.wait([append(['b', 'c']), append(['d']), append(['e', 'f'])]);
    expect(player.sources, ['a', 'b', 'c', 'd', 'e', 'f']);
  });

  test('a failed load leaves nothing to extend', () async {
    var added = false;
    await PlayerQueueSync.catchUp(
      pendingLoad: Future<void>.error(StateError('interrupted')),
      playerLength: () => 0,
      modelLength: () => 5,
      addFrom: (_) async => added = true,
    );
    expect(added, isFalse);
  });

  test('a failing op does not block the ones after it', () async {
    final sync = PlayerQueueSync();
    final failed = sync.serial(() async => throw StateError('boom'));
    var ran = false;
    final next = sync.serial(() async => ran = true);
    await expectLater(failed, throwsStateError);
    await next;
    expect(ran, isTrue);
  });
}
