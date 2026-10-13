import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'package:eq_app/models/track_extras.dart';
import 'package:eq_app/services/connect/connect_protocol.dart';
import 'package:eq_app/services/connect/connect_state_publisher.dart';
import 'package:eq_app/services/connect/remote/connect_remote_session.dart';
import 'package:eq_app/services/connect/remote/connect_transfer.dart';

const me = 'phone';

SongModel song(int id, {String? videoId}) => SongModel({
      '_id': id,
      '_data': videoId == null ? '/music/$id.mp3' : 'https://music.youtube.com/watch?v=$videoId',
      'title': 'Song $id',
      '_display_name': 'x',
      '_display_name_wo_ext': 'x',
      '_size': 0,
      'is_music': true,
      ...?(videoId == null ? null : {TrackKeys.videoId: videoId}),
    });

DeviceInfo dev(String id, {String? name, bool online = true}) => DeviceInfo(
      id: id,
      kind: id == me ? DeviceKind.mobile : DeviceKind.desktop,
      name: name ?? 'Name $id',
      platform: null,
      appVersion: null,
      caps: const [ConnectCap.player],
      online: online,
      lastSeenAt: 'x',
    );

class FakeSource implements ConnectStateSource {
  FakeSource({this.snapshot});
  ConnectSnapshot? snapshot;

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  ConnectSnapshot read() =>
      snapshot ??
      const ConnectSnapshot(
        track: null,
        playing: false,
        position: Duration.zero,
        duration: null,
        volume: 1,
        shuffle: false,
        repeat: ConnectRepeat.off,
        upcoming: [],
      );
}

ConnectSnapshot playingSnapshot(SongModel track, List<SongModel> upcoming,
        {int positionMs = 42000}) =>
    ConnectSnapshot(
      track: track,
      playing: true,
      position: Duration(milliseconds: positionMs),
      duration: const Duration(minutes: 3),
      volume: 1,
      shuffle: false,
      repeat: ConnectRepeat.off,
      upcoming: [
        for (var i = 0; i < upcoming.length; i++)
          UpcomingSong('q-${upcoming[i].id}', upcoming[i]),
      ],
    );

class Rig {
  Rig({String? active = 'desk', FakeSource? source, this.playAck, this.cmdAck}) {
    session = ConnectRemoteSession(
      selfId: me,
      send: (frame) {
        sent.add(frame);
        if (frame is CmdFrame) {
          scheduleMicrotask(() => session.onFrame(cmdAck?.call(frame) ?? AckFrame.ok(frame.id)));
        }
        if (frame is SelectFrame) selects.add(frame.deviceId);
        return true;
      },
      hubNowMs: () => hubNow,
    );
    session.onFrame(WelcomeFrame(
      v: 1,
      deviceId: me,
      serverTime: hubNow,
      devices: [dev(me), dev('desk', name: 'Desk'), dev('tab', name: 'Tab')],
      activeDeviceId: active,
      states: {
        'desk': StampedState(
          state: PlayerState(
            seq: 1,
            track: yt('a'),
            playing: true,
            positionMs: 10000,
            durationMs: 200000,
            volume: 1,
            shuffle: false,
            repeat: ConnectRepeat.off,
            queue: [
              QueueEntry(uid: 'q1', track: yt('b')),
              QueueEntry(uid: 'q2', track: LocalTrackRef(deviceId: 'desk', id: '/x.mp3', title: 'Their file', artist: null, album: null, durationMs: null)),
              QueueEntry(uid: 'q3', track: yt('c')),
            ],
          ),
          at: hubNow - 5000,
        ),
      },
    ));
    this.source = source ?? FakeSource();
    transfer = ConnectTransfer(
      session: session,
      selfId: me,
      localState: this.source,
      pauseLocal: () async => paused++,
      playLocal: (command) async {
        localPlays.add(command);
        return playAck ?? AckFrame.ok('local');
      },
      select: (id) {
        selects.add(id);
        return true;
      },
      nameOf: (id) => id == me ? 'This phone' : 'Name of $id',
    );
  }

  late final ConnectRemoteSession session;
  late final FakeSource source;
  late final ConnectTransfer transfer;
  final AckFrame? playAck;
  final AckFrame Function(CmdFrame)? cmdAck;
  final sent = <ConnectFrame>[];
  final selects = <String?>[];
  final localPlays = <PlayCommand>[];
  int paused = 0;
  int hubNow = 1000000;

  List<CmdFrame> get cmds => sent.whereType<CmdFrame>().toList();
}

TrackRef yt(String id) => YtTrackRef(
      videoId: id,
      title: 'Yt $id',
      artist: null,
      album: null,
      durationMs: null,
      artUrl: null,
    );

void main() {
  group('phone -> other', () {
    test('plays its track + queue at its position, then pauses and selects',
        () async {
      final r = Rig(
        active: me,
        source: FakeSource(
          snapshot: playingSnapshot(song(1, videoId: 'p1'), [
            song(2, videoId: 'p2'),
            song(3),
          ]),
        ),
      );
      final result = await r.transfer.moveTo('desk');
      expect(result.ok, isTrue);
      expect(result.dropped, 1, reason: 'the local song stays behind');
      final play = r.cmds.single.cmd as PlayCommand;
      expect(r.cmds.single.to, 'desk');
      expect(play.items.map((i) => (i as YtTrackRef).videoId), ['p1', 'p2']);
      expect(play.index, 0);
      expect(play.positionMs, 42000);
      expect(r.paused, 1);
      expect(r.selects, ['desk']);
    });

    test('does not pause or select if the target refuses', () async {
      final r = Rig(
        active: me,
        source: FakeSource(
            snapshot: playingSnapshot(song(1, videoId: 'p1'), const [])),
        cmdAck: (f) => AckFrame.failed(f.id, AckError.nothingPlayable),
      );
      final result = await r.transfer.moveTo('desk');
      expect(result.ok, isFalse);
      expect(result.message, contains('Name of desk'));
      expect(r.paused, 0);
      expect(r.selects, isEmpty);
    });

    test('a local head song cannot move', () async {
      final r = Rig(
        active: me,
        source: FakeSource(snapshot: playingSnapshot(song(1), [song(2, videoId: 'x')])),
      );
      final result = await r.transfer.moveTo('desk');
      expect(result.ok, isFalse);
      expect(result.message, contains("'Song 1' is only on This phone"));
      expect(r.cmds, isEmpty);
      expect(r.paused, 0);
    });

    test('an offline target says so', () async {
      final r = Rig(
        active: me,
        source: FakeSource(
            snapshot: playingSnapshot(song(1, videoId: 'p1'), const [])),
        cmdAck: (f) => AckFrame.failed(f.id, AckError.offline),
      );
      final result = await r.transfer.moveTo('desk');
      expect(result.message, contains('offline'));
    });
  });

  group('other -> phone', () {
    test('feeds the interpolated remote state to the local play handler, '
        'then pauses the old device', () async {
      final r = Rig();
      final result = await r.transfer.moveTo(me);
      expect(result.ok, isTrue);
      expect(result.dropped, 1, reason: 'the desktop file stays behind');
      final play = r.localPlays.single;
      expect(play.items.map((i) => (i as YtTrackRef).videoId), ['a', 'b', 'c']);
      expect(play.index, 0);
      expect(play.positionMs, 15000, reason: '10 s + 5 s of hub time');
      // Old device paused; this phone is not "selected" by us (Claim does it).
      final pause = r.cmds.single;
      expect(pause.to, 'desk');
      expect(pause.cmd, isA<PauseCommand>());
      expect(r.selects, isEmpty);
      expect(r.paused, 0);
    });

    test('does not pause the old device when the phone cannot play it',
        () async {
      final r = Rig(playAck: AckFrame.failed('local', AckError.nothingPlayable));
      final result = await r.transfer.moveTo(me);
      expect(result.ok, isFalse);
      expect(result.message, contains('This phone could not take over'));
      expect(r.cmds, isEmpty);
    });

    test('a head song that is the desktop\'s own file cannot move', () async {
      final r = Rig();
      r.session.onFrame(StampedStateFrame(
        deviceId: 'desk',
        state: StampedState(
          state: PlayerState(
            seq: 9,
            track: LocalTrackRef(deviceId: 'desk', id: '/f.mp3', title: 'Their file', artist: null, album: null, durationMs: null),
            playing: true,
            positionMs: 0,
            durationMs: null,
            volume: 1,
            shuffle: false,
            repeat: ConnectRepeat.off,
            queue: const [],
          ),
          at: r.hubNow,
        ),
      ));
      final result = await r.transfer.moveTo(me);
      expect(result.ok, isFalse);
      expect(result.message, contains("'Their file' is only on Name of desk"));
      expect(r.localPlays, isEmpty);
    });
  });

  group('other -> other', () {
    test('plays on the new device, pauses the old, selects the new', () async {
      final r = Rig();
      final result = await r.transfer.moveTo('tab');
      expect(result.ok, isTrue);
      expect(result.dropped, 1);
      final cmds = r.cmds;
      expect(cmds.first.to, 'tab');
      expect((cmds.first.cmd as PlayCommand).positionMs, 15000);
      expect(cmds[1].to, 'desk');
      expect(cmds[1].cmd, isA<PauseCommand>());
      expect(r.selects, ['tab']);
    });
  });

  group('degenerate', () {
    test('moving to the device already playing does nothing', () async {
      final r = Rig();
      final result = await r.transfer.moveTo('desk');
      expect(result.ok, isTrue);
      expect(r.cmds, isEmpty);
      expect(r.selects, isEmpty);
    });

    test('with nothing playing anywhere it only selects', () async {
      final r = Rig(active: null);
      r.session.onFrame(DevicesFrame(
          devices: [dev(me), dev('desk'), dev('tab')], activeDeviceId: null));
      final result = await r.transfer.moveTo('tab');
      expect(result.ok, isTrue);
      expect(r.selects, ['tab']);
      expect(r.cmds, isEmpty);
    });

    test('transfer from a source with no state only selects', () async {
      final r = Rig();
      final result = await r.transfer.transfer(from: 'tab', to: 'desk');
      expect(result.ok, isTrue);
      expect(r.selects, ['desk']);
      expect(r.cmds, isEmpty);
    });

    test('a remote state with no track only selects', () async {
      final r = Rig();
      r.session.onFrame(StampedStateFrame(
        deviceId: 'desk',
        state: StampedState(
          state: const PlayerState(
            seq: 9,
            track: null,
            playing: false,
            positionMs: 0,
            durationMs: null,
            volume: 1,
            shuffle: false,
            repeat: ConnectRepeat.off,
            queue: [],
          ),
          at: r.hubNow,
        ),
      ));
      final result = await r.transfer.moveTo('tab');
      expect(result.ok, isTrue);
      expect(r.selects, ['tab']);
      expect(r.cmds, isEmpty);
    });

    test("a file that lives on the target itself can move to it", () async {
      final r = Rig();
      r.session.onFrame(StampedStateFrame(
        deviceId: 'tab',
        state: StampedState(
          state: PlayerState(
            seq: 9,
            track: yt('t1'),
            playing: true,
            positionMs: 0,
            durationMs: null,
            volume: 1,
            shuffle: false,
            repeat: ConnectRepeat.off,
            queue: [
              QueueEntry(
                uid: 'u',
                track: LocalTrackRef(deviceId: 'desk', id: '/d.mp3', title: 'D', artist: null, album: null, durationMs: null),
              ),
            ],
          ),
          at: r.hubNow,
        ),
      ));
      final result = await r.transfer.transfer(from: 'tab', to: 'desk');
      expect(result.dropped, 0);
      expect((r.cmds.first.cmd as PlayCommand).items, hasLength(2));
    });
  });
}
