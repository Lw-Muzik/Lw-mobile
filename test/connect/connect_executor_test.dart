import 'dart:async';

import 'package:eq_app/services/connect/connect_executor.dart';
import 'package:eq_app/services/connect/connect_protocol.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';

const me = '6f1d2c3b-4a59-4e6f-8a7b-9c0d1e2f3a4b';
const someoneElse = '0b9a8c7d-6e5f-4a3b-8c2d-1e0f9a8b7c6d';

SongModel song(int id) => SongModel({
      '_id': id,
      '_data': '/music/$id.mp3',
      'title': 'Song $id',
      '_display_name': '$id.mp3',
      '_display_name_wo_ext': '$id',
      '_size': 1,
      'file_extension': 'mp3',
      'is_music': true,
    });

YtTrackRef yt(String id) => YtTrackRef(videoId: id, title: 'YT $id');

LocalTrackRef local(int id, {String owner = me}) =>
    LocalTrackRef(deviceId: owner, id: '$id', title: 'Song $id');

class FakeLibrary implements ConnectLibrary {
  FakeLibrary(Iterable<int> ids) : songs = {for (final id in ids) id: song(id)};

  final Map<int, SongModel> songs;
  final List<Set<int>> lookups = [];

  @override
  Future<Map<int, SongModel>> songsByIds(Iterable<int> ids) async {
    lookups.add(ids.toSet());
    return {for (final id in ids) id: ?songs[id]};
  }

  @override
  Future<({int total, List<SongModel> songs})> page({
    required int offset,
    required int limit,
    String? query,
  }) async =>
      (total: songs.length, songs: songs.values.skip(offset).take(limit).toList());
}

/// Records what the executor asked for, in order.
class FakePlayer implements ConnectPlayer {
  @override
  bool available = true;
  @override
  bool hasQueue = true;

  final List<String> calls = [];
  PlayPlan? lastPlan;
  List<Playable>? lastEnqueued;
  Set<String> uids = {'q-1', 'q-2'};
  Object? failWith;

  /// When set, the next action waits on this before completing.
  Completer<void>? hold;

  Future<void> _record(String call) async {
    calls.add(call);
    if (failWith != null) throw failWith!;
    final h = hold;
    if (h != null) await h.future;
  }

  @override
  Future<void> play(PlayPlan plan) {
    lastPlan = plan;
    return _record('play');
  }

  @override
  Future<void> enqueue(List<Playable> items, EnqueueMode mode) {
    lastEnqueued = items;
    return _record('enqueue ${mode.name}');
  }

  @override
  Future<void> pause() => _record('pause');
  @override
  Future<void> resume() => _record('resume');
  @override
  Future<void> stop() => _record('stop');
  @override
  Future<void> next() => _record('next');
  @override
  Future<void> prev() => _record('prev');
  @override
  Future<void> seek(Duration position) => _record('seek ${position.inMilliseconds}');

  @override
  Future<bool> jump(String uid) async {
    calls.add('jump $uid');
    return uids.contains(uid);
  }

  @override
  Future<void> setVolume(double value) => _record('volume $value');
  @override
  Future<void> setShuffle(bool on) => _record('shuffle $on');
  @override
  Future<void> setRepeat(ConnectRepeat mode) => _record('repeat ${mode.name}');
}

CmdFrame cmd(Command c, [String id = 'c-1']) => CmdFrame(id: id, from: 'web', cmd: c);

Map<String, Object?> ackJson(AckFrame ack) => ack.toJson();

void main() {
  late FakePlayer player;
  late FakeLibrary library;
  late ConnectExecutor executor;

  setUp(() {
    player = FakePlayer();
    library = FakeLibrary([18342, 7, 8]);
    executor = ConnectExecutor(player: player, library: library, deviceId: me);
  });

  Future<Map<String, Object?>> run(Command c, [String id = 'c-1']) async {
    final ack = await executor.execute(cmd(c, id));
    // Let anything started in the background record itself.
    await pumpEventQueue();
    return ackJson(ack);
  }

  group('play', () {
    test('a YouTube list plays from the index, positioned, no radio', () async {
      final ack = await run(PlayCommand(
        items: [yt('a'), yt('b'), yt('c')],
        index: 1,
        positionMs: 61250,
        radio: false,
      ));
      expect(ack, {'t': 'ack', 'id': 'c-1', 'ok': true});
      final plan = player.lastPlan as YtListPlan;
      expect(plan.tracks.map((t) => t.videoId), ['b', 'c']);
      expect(plan.radio, isFalse);
      expect(plan.startAt, const Duration(milliseconds: 61250));
    });

    test('radio:true plays the tapped result and lets radio follow', () async {
      await run(PlayCommand(items: [yt('a'), yt('b')], index: 0, radio: true));
      final plan = player.lastPlan as YtListPlan;
      expect(plan.radio, isTrue);
      expect(plan.tracks.first.videoId, 'a');
    });

    test('radio:true on one of this phone\'s songs starts a library station',
        () async {
      await run(PlayCommand(items: [local(7)], index: 0, radio: true));
      final plan = player.lastPlan as LocalStationPlan;
      expect(plan.seed.id, 7);
    });

    test('this phone\'s songs: the whole list queues, starting at the index',
        () async {
      await run(PlayCommand(
        items: [local(7), local(8), local(18342)],
        index: 1,
      ));
      final plan = player.lastPlan as LocalListPlan;
      expect(plan.songs.map((s) => s.id), [7, 8, 18342]);
      expect(plan.index, 1);
      expect(library.lookups.single, {7, 8, 18342});
    });

    test('another device\'s local ref is skipped and never looked up', () async {
      // Song 8 exists here — but the ref names a different device's song 8.
      await run(PlayCommand(
        items: [local(8, owner: someoneElse), local(7)],
        index: 0,
        positionMs: 5000,
      ));
      final plan = player.lastPlan as LocalListPlan;
      expect(plan.songs.map((s) => s.id), [7]);
      expect(plan.index, 0);
      expect(library.lookups.single, {7});
      // The position was for the song that was skipped.
      expect(plan.startAt, isNull);
    });

    test('a local song no longer in the library is skipped', () async {
      await run(PlayCommand(items: [local(999), yt('a')], index: 0));
      final plan = player.lastPlan as YtListPlan;
      expect(plan.tracks.map((t) => t.videoId), ['a']);
    });

    test('mixed sources play as a mix', () async {
      await run(PlayCommand(items: [yt('a'), local(7), yt('b')], index: 0));
      final plan = player.lastPlan as MixedListPlan;
      expect(plan.items, hasLength(3));
      expect(plan.items[1], isA<LocalPlayable>());
    });

    test('the contract fixture: two yt and this phone\'s song', () async {
      // cmd.play.from.json, addressed to this very device.
      await run(PlayCommand(
        items: [yt('dQw4w9WgXcQ'), yt('kJQP7kiw5Fk'), local(18342)],
        index: 0,
        positionMs: 0,
        radio: false,
      ));
      expect(player.lastPlan, isA<MixedListPlan>());
    });

    test('nothing playable from the index on is nothing_playable', () async {
      final ack = await run(PlayCommand(
        items: [
          local(7),
          local(1, owner: someoneElse),
          const OtherTrackRef(title: 'Capital FM'),
        ],
        index: 1,
      ));
      expect(ack, {
        't': 'ack',
        'id': 'c-1',
        'ok': false,
        'error': 'nothing_playable',
      });
      expect(player.calls, isEmpty);
    });

    test('an empty list is nothing_playable; a bad index is failed', () async {
      expect((await run(const PlayCommand(items: [], index: 0)))['error'],
          'nothing_playable');
      expect(
        (await run(PlayCommand(items: [yt('a')], index: 3)))['error'],
        'failed',
      );
      expect(player.calls, isEmpty);
    });

    test('acks before playback finishes starting', () async {
      player.hold = Completer<void>();
      final ack = await executor.execute(cmd(PlayCommand(items: [yt('a')], index: 0)));
      expect(ack.ok, isTrue);
      expect(player.hold!.isCompleted, isFalse);
      player.hold!.complete();
    });

    test('a failure after acceptance does not change the ack', () async {
      player.failWith = StateError('resolve failed');
      final ack = await run(PlayCommand(items: [yt('a')], index: 0));
      expect(ack['ok'], isTrue);
    });
  });

  group('enqueue', () {
    test('next and end reach the player with only what can play', () async {
      await run(EnqueueCommand(
        items: [yt('a'), local(7), local(7, owner: someoneElse)],
        mode: EnqueueMode.next,
      ));
      expect(player.calls, ['enqueue next']);
      expect(player.lastEnqueued, hasLength(2));

      await run(EnqueueCommand(items: [yt('b')], mode: EnqueueMode.end));
      expect(player.calls.last, 'enqueue end');
    });

    test('onto an empty queue it plays instead', () async {
      player.hasQueue = false;
      await run(EnqueueCommand(items: [yt('a'), yt('b')], mode: EnqueueMode.end));
      expect(player.calls, ['play']);
      expect((player.lastPlan as YtListPlan).tracks, hasLength(2));
    });

    test('nothing playable is nothing_playable', () async {
      final ack = await run(EnqueueCommand(
        items: [local(7, owner: someoneElse)],
        mode: EnqueueMode.end,
      ));
      expect(ack['error'], 'nothing_playable');
      expect(player.calls, isEmpty);
    });
  });

  group('transport', () {
    test('each command maps to exactly one explicit action', () async {
      final expected = <Command, String>{
        const PauseCommand(): 'pause',
        const ResumeCommand(): 'resume',
        const StopCommand(): 'stop',
        const NextCommand(): 'next',
        const PrevCommand(): 'prev',
        const SeekCommand(90000): 'seek 90000',
        const VolumeCommand(0.35): 'volume 0.35',
        const ShuffleCommand(true): 'shuffle true',
        const ShuffleCommand(false): 'shuffle false',
        const RepeatCommand(ConnectRepeat.one): 'repeat one',
        const RepeatCommand(ConnectRepeat.all): 'repeat all',
        const RepeatCommand(ConnectRepeat.off): 'repeat off',
      };
      for (final entry in expected.entries) {
        player.calls.clear();
        final ack = await run(entry.key);
        expect(ack['ok'], isTrue, reason: entry.key.type);
        expect(player.calls, [entry.value], reason: entry.key.type);
      }
    });

    test('pause twice is two pauses, not a toggle back to playing', () async {
      await run(const PauseCommand());
      await run(const PauseCommand());
      expect(player.calls, ['pause', 'pause']);
    });

    test('seek before zero seeks to zero; volume is clamped to 0..1', () async {
      await run(const SeekCommand(-500));
      await run(const VolumeCommand(1.7));
      await run(const VolumeCommand(-0.2));
      expect(player.calls, ['seek 0', 'volume 1.0', 'volume 0.0']);
    });

    test('a volume that is not a number is failed', () async {
      final ack = await run(const VolumeCommand(double.nan));
      expect(ack['error'], 'failed');
      expect(player.calls, isEmpty);
    });

    test('resume with no queue is nothing_playable', () async {
      player.hasQueue = false;
      expect((await run(const ResumeCommand()))['error'], 'nothing_playable');
    });

    test('jump to a known uid is ok; an unknown one is failed', () async {
      expect((await run(const JumpCommand('q-2')))['ok'], isTrue);
      final ack = await run(const JumpCommand('q-404'));
      expect(ack, {'t': 'ack', 'id': 'c-1', 'ok': false, 'error': 'failed'});
    });

    test('an action that throws is failed', () async {
      player.failWith = StateError('no player');
      expect((await run(const PauseCommand()))['error'], 'failed');
    });

    test('an action still running after acceptWithin is acked as accepted', () {
      // Real timers would make this test slow; a short window does the same.
      executor = ConnectExecutor(
        player: player,
        library: library,
        deviceId: me,
        acceptWithin: const Duration(milliseconds: 20),
      );
      player.hold = Completer<void>();
      return executor.execute(cmd(const ShuffleCommand(true))).then((ack) {
        expect(ack.ok, isTrue);
        expect(player.hold!.isCompleted, isFalse);
        player.hold!.complete();
      });
    });
  });

  group('refusals', () {
    test('an unknown command type is unsupported', () async {
      final ack = await run(const UnknownCommand('crossfade', {'type': 'crossfade'}));
      expect(ack['error'], 'unsupported');
    });

    test('in equalizer-only mode every command is unsupported', () async {
      player.available = false;
      for (final c in [
        const PauseCommand(),
        PlayCommand(items: [yt('a')], index: 0),
      ]) {
        expect((await run(c))['error'], 'unsupported');
      }
      expect(player.calls, isEmpty);
    });
  });

  group('ordering', () {
    test('commands are accepted in arrival order', () async {
      // The play's local lookup is slow; the pause behind it must wait.
      final slow = Completer<void>();
      final slowLibrary = _SlowLibrary(library, slow.future);
      executor = ConnectExecutor(player: player, library: slowLibrary, deviceId: me);

      final first = executor.execute(cmd(PlayCommand(items: [local(7)], index: 0), 'c-1'));
      final second = executor.execute(cmd(const PauseCommand(), 'c-2'));
      await pumpEventQueue();
      expect(player.calls, isEmpty);

      slow.complete();
      final acks = await Future.wait([first, second]);
      await pumpEventQueue();
      expect(acks.map((a) => a.id), ['c-1', 'c-2']);
      expect(player.calls, ['play', 'pause']);
    });
  });

  group('execution order', () {
    test('a pause behind a slow play is acked, then runs after the play',
        () async {
      executor = ConnectExecutor(
        player: player,
        library: library,
        deviceId: me,
        acceptWithin: const Duration(milliseconds: 20),
      );
      final slowPlay = player.hold = Completer<void>();

      final playAck = await executor.execute(cmd(PlayCommand(items: [yt('a')], index: 0), 'c-1'));
      expect(playAck.ok, isTrue);
      player.hold = null;

      // The play's first track is still resolving: the pause must not reach
      // the player before it, or the music starts after being paused.
      final pauseAck = await executor.execute(cmd(const PauseCommand(), 'c-2'));
      expect(pauseAck.ok, isTrue, reason: 'accepted while waiting its turn');
      expect(player.calls, ['play']);

      slowPlay.complete();
      await pumpEventQueue();
      expect(player.calls, ['play', 'pause']);
    });

    test('a failed action does not stop the ones behind it', () async {
      player.failWith = StateError('boom');
      expect((await run(const NextCommand()))['ok'], isFalse);
      player.failWith = null;
      expect((await run(const PrevCommand()))['ok'], isTrue);
      expect(player.calls, ['next', 'prev']);
    });
  });

  group('planPlay', () {
    test('items before the index never start playback', () {
      final plan = planPlay(
        [LocalPlayable(song(7)), null],
        1,
      );
      expect(plan, isNull);
    });

    test('position applies only to the item that was asked for', () {
      final kept = planPlay([YtPlayable(_t('a'))], 0, position: const Duration(seconds: 9));
      expect((kept as YtListPlan).startAt, const Duration(seconds: 9));
      final skipped = planPlay(
        [null, YtPlayable(_t('a'))],
        0,
        position: const Duration(seconds: 9),
      );
      expect((skipped as YtListPlan).startAt, isNull);
    });
  });
}

YtTrack _t(String id) => YtTrack(videoId: id, title: id);

class _SlowLibrary implements ConnectLibrary {
  _SlowLibrary(this._inner, this._gate);
  final ConnectLibrary _inner;
  final Future<void> _gate;

  @override
  Future<Map<int, SongModel>> songsByIds(Iterable<int> ids) async {
    await _gate;
    return _inner.songsByIds(ids);
  }

  @override
  Future<({int total, List<SongModel> songs})> page({
    required int offset,
    required int limit,
    String? query,
  }) =>
      _inner.page(offset: offset, limit: limit, query: query);
}
