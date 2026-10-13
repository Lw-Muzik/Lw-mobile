import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/services/connect/connect_protocol.dart';
import 'package:eq_app/services/connect/remote/connect_remote_session.dart';

const self = 'phone';

DeviceInfo device(
  String id, {
  bool online = true,
  bool player = true,
  DeviceKind kind = DeviceKind.desktop,
}) =>
    DeviceInfo(
      id: id,
      kind: kind,
      name: 'Name of $id',
      platform: null,
      appVersion: null,
      caps: player ? const [ConnectCap.player, ConnectCap.yt] : const [],
      online: online,
      lastSeenAt: '2026-01-01T00:00:00Z',
    );

TrackRef yt(String id) => YtTrackRef(
      videoId: id,
      title: 't$id',
      artist: 'a',
      album: null,
      durationMs: 200000,
      artUrl: null,
    );

PlayerState state({
  int seq = 1,
  bool playing = true,
  int positionMs = 10000,
  int? durationMs = 200000,
  String video = 'v1',
  List<QueueEntry> queue = const [],
}) =>
    PlayerState(
      seq: seq,
      track: yt(video),
      playing: playing,
      positionMs: positionMs,
      durationMs: durationMs,
      volume: 0.5,
      shuffle: false,
      repeat: ConnectRepeat.off,
      queue: queue,
    );

class Rig {
  Rig({this.sends = true}) {
    session = ConnectRemoteSession(
      selfId: self,
      send: (frame) {
        if (!sends) return false;
        sent.add(frame);
        return true;
      },
      hubNowMs: () => hubNow,
    );
  }

  late final ConnectRemoteSession session;
  final bool sends;
  final sent = <ConnectFrame>[];
  int hubNow = 1000000;

  final phone = device(self, kind: DeviceKind.mobile);
  final desk = device('desk');

  WelcomeFrame welcome({
    List<DeviceInfo>? devices,
    String? active = 'desk',
    Map<String, StampedState> states = const {},
  }) =>
      WelcomeFrame(
        v: 1,
        deviceId: self,
        serverTime: hubNow,
        devices: devices ?? [phone, desk],
        activeDeviceId: active,
        states: states,
      );

  void stateFrame(String id, PlayerState s, {int? at}) => session.onFrame(
        StampedStateFrame(
          deviceId: id,
          state: StampedState(state: s, at: at ?? hubNow),
        ),
      );

  CmdFrame get lastCmd => sent.whereType<CmdFrame>().last;
}

void main() {
  group('remote target', () {
    test('is the active device when it is another online player', () {
      final r = Rig();
      r.session.onFrame(r.welcome());
      expect(r.session.isRemote, isTrue);
      expect(r.session.remoteTarget?.id, 'desk');
    });

    test('is null when this phone is active', () {
      final r = Rig();
      r.session.onFrame(r.welcome(active: self));
      expect(r.session.isRemote, isFalse);
    });

    test('is null with no active device', () {
      final r = Rig();
      r.session.onFrame(r.welcome(active: null));
      expect(r.session.isRemote, isFalse);
    });

    test('is null when the active device is offline', () {
      final r = Rig();
      r.session.onFrame(r.welcome(devices: [r.phone, device('desk', online: false)]));
      expect(r.session.isRemote, isFalse);
    });

    test('is null when the active device is not a player', () {
      final r = Rig();
      final web = device('web', player: false, kind: DeviceKind.web);
      r.session.onFrame(r.welcome(devices: [r.phone, web], active: 'web'));
      expect(r.session.isRemote, isFalse);
    });

    test('follows the devices frame', () {
      final r = Rig();
      r.session.onFrame(r.welcome(active: self));
      r.session.onFrame(DevicesFrame(devices: [r.phone, r.desk], activeDeviceId: 'desk'));
      expect(r.session.isRemote, isTrue);
      r.session.onFrame(DevicesFrame(devices: [r.phone, r.desk], activeDeviceId: self));
      expect(r.session.isRemote, isFalse);
    });

    test('otherPlayers lists online players but not this phone', () {
      final r = Rig();
      final web = device('web', player: false, kind: DeviceKind.web);
      r.session.onFrame(r.welcome(devices: [
        r.phone,
        r.desk,
        device('off', online: false),
        web,
      ]));
      expect([for (final d in r.session.otherPlayers) d.id], ['desk']);
    });
  });

  group('went offline', () {
    test('emits once when the target drops while still active', () {
      final r = Rig();
      final events = <RemoteEvent>[];
      r.session.events.listen(events.add);
      r.session.onFrame(r.welcome());
      r.session.onFrame(DevicesFrame(
        devices: [r.phone, device('desk', online: false)],
        activeDeviceId: 'desk',
      ));
      expect(r.session.isRemote, isFalse);
      expect(events, hasLength(1));
      expect((events.single as RemoteWentOffline).deviceName, 'Name of desk');
    });

    test('no notice when this phone takes over', () {
      final r = Rig();
      final events = <RemoteEvent>[];
      r.session.events.listen(events.add);
      r.session.onFrame(r.welcome());
      r.session.onFrame(DevicesFrame(devices: [r.phone, r.desk], activeDeviceId: self));
      expect(events, isEmpty);
    });

    test('no notice when another device takes over', () {
      final r = Rig();
      final events = <RemoteEvent>[];
      r.session.events.listen(events.add);
      final other = device('tab');
      r.session.onFrame(r.welcome(devices: [r.phone, r.desk, other]));
      r.session.onFrame(DevicesFrame(
        devices: [r.phone, r.desk, other],
        activeDeviceId: 'tab',
      ));
      expect(events, isEmpty);
      expect(r.session.remoteTarget?.id, 'tab');
    });

    test('no notice when the active device moves to an offline one', () {
      final r = Rig();
      final events = <RemoteEvent>[];
      r.session.events.listen(events.add);
      final tab = device('tab', online: false);
      r.session.onFrame(r.welcome(devices: [r.phone, r.desk, tab]));
      r.session.onFrame(DevicesFrame(
        devices: [r.phone, r.desk, tab],
        activeDeviceId: 'tab',
      ));
      expect(r.session.isRemote, isFalse);
      expect(events, isEmpty);
    });

    test('no notice when the target merely stops being a player', () {
      final r = Rig();
      final events = <RemoteEvent>[];
      r.session.events.listen(events.add);
      r.session.onFrame(r.welcome());
      r.session.onFrame(DevicesFrame(
        devices: [r.phone, device('desk', player: false)],
        activeDeviceId: 'desk',
      ));
      expect(r.session.isRemote, isFalse);
      expect(events, isEmpty);
    });

    test('a device removed from the list counts as gone', () {
      final r = Rig();
      final events = <RemoteEvent>[];
      r.session.events.listen(events.add);
      r.session.onFrame(r.welcome());
      r.session.onFrame(DevicesFrame(devices: [r.phone], activeDeviceId: 'desk'));
      expect(events, hasLength(1));
    });
  });

  group('state handling', () {
    test('welcome states are read; older seq is dropped; newer replaces', () {
      final r = Rig();
      r.session.onFrame(r.welcome(
        states: {'desk': StampedState(state: state(seq: 5, video: 'a'), at: r.hubNow)},
      ));
      expect((r.session.nowPlaying()!.track as YtTrackRef).videoId, 'a');
      r.stateFrame('desk', state(seq: 4, video: 'old'));
      expect((r.session.nowPlaying()!.track as YtTrackRef).videoId, 'a');
      r.stateFrame('desk', state(seq: 5, video: 'same'));
      expect((r.session.nowPlaying()!.track as YtTrackRef).videoId, 'a');
      r.stateFrame('desk', state(seq: 6, video: 'b'));
      expect((r.session.nowPlaying()!.track as YtTrackRef).videoId, 'b');
    });

    test('seq is tracked per device', () {
      final r = Rig();
      final tab = device('tab');
      r.session.onFrame(r.welcome(devices: [r.phone, r.desk, tab]));
      r.stateFrame('desk', state(seq: 10, video: 'd'));
      r.stateFrame('tab', state(seq: 1, video: 't'));
      expect(r.session.stateOf('tab')!.state.seq, 1);
      expect(r.session.stateOf('desk')!.state.seq, 10);
    });

    test('a device going offline is forgotten', () {
      final r = Rig();
      r.session.onFrame(r.welcome());
      r.stateFrame('desk', state(seq: 3));
      r.session.onFrame(DevicesFrame(
        devices: [r.phone, device('desk', online: false)],
        activeDeviceId: 'desk',
      ));
      expect(r.session.stateOf('desk'), isNull);
      // And a lower seq after coming back online is accepted.
      r.session.onFrame(DevicesFrame(devices: [r.phone, r.desk], activeDeviceId: 'desk'));
      r.stateFrame('desk', state(seq: 1));
      expect(r.session.stateOf('desk')!.state.seq, 1);
    });

    test('a welcome replaces every state', () {
      final r = Rig();
      r.session.onFrame(r.welcome());
      r.stateFrame('desk', state(seq: 3));
      r.session.onFrame(r.welcome());
      expect(r.session.stateOf('desk'), isNull);
    });

    test('this phone\'s own state is ignored', () {
      final r = Rig();
      r.session.onFrame(r.welcome());
      r.stateFrame(self, state(seq: 3));
      expect(r.session.stateOf(self), isNull);
    });

    test('notifies listeners only for the target\'s state', () {
      final r = Rig();
      final tab = device('tab');
      r.session.onFrame(r.welcome(devices: [r.phone, r.desk, tab]));
      var n = 0;
      r.session.addListener(() => n++);
      r.stateFrame('tab', state(seq: 1));
      expect(n, 0);
      r.stateFrame('desk', state(seq: 1));
      expect(n, 1);
    });
  });

  group('interpolation', () {
    test('playing advances by hub time since the frame', () {
      final r = Rig();
      r.session.onFrame(r.welcome(
        states: {
          'desk': StampedState(
            state: state(positionMs: 10000),
            at: r.hubNow - 4000,
          ),
        },
      ));
      expect(r.session.positionMs(), 14000);
      r.hubNow += 1500;
      expect(r.session.positionMs(), 15500);
    });

    test('paused does not advance', () {
      final r = Rig();
      r.session.onFrame(r.welcome(
        states: {
          'desk': StampedState(
            state: state(playing: false, positionMs: 10000),
            at: r.hubNow - 4000,
          ),
        },
      ));
      expect(r.session.positionMs(), 10000);
    });

    test('is clamped to the duration and to zero', () {
      final r = Rig();
      r.session.onFrame(r.welcome(
        states: {
          'desk': StampedState(
            state: state(positionMs: 199000),
            at: r.hubNow - 60000,
          ),
        },
      ));
      expect(r.session.positionMs(), 200000);
      r.stateFrame('desk', state(seq: 9, positionMs: 100), at: r.hubNow + 5000);
      expect(r.session.positionMs(), 0); // a frame "from the future" never goes negative
    });

    test('no duration means no upper clamp', () {
      final r = Rig();
      r.session.onFrame(r.welcome(
        states: {
          'desk': StampedState(
            state: state(positionMs: 1000, durationMs: null),
            at: r.hubNow - 5000,
          ),
        },
      ));
      expect(r.session.positionMs(), 6000);
    });

    test('nowPlaying is null outside remote mode', () {
      final r = Rig();
      r.session.onFrame(r.welcome(active: self));
      expect(r.session.nowPlaying(), isNull);
    });
  });

  group('commands', () {
    test('cmd sends a cmd frame to the device and resolves on its ack', () async {
      final r = Rig();
      r.session.onFrame(r.welcome());
      final future = r.session.cmd('desk', const NextCommand());
      final frame = r.lastCmd;
      expect(frame.to, 'desk');
      expect(frame.cmd, isA<NextCommand>());
      r.session.onFrame(AckFrame.ok(frame.id));
      final ack = await future;
      expect(ack.ok, isTrue);
      expect(ack.id, frame.id);
    });

    test('ids are unique', () {
      final r = Rig();
      r.session.cmd('desk', const NextCommand()).ignore();
      r.session.cmd('desk', const NextCommand()).ignore();
      final ids = r.sent.whereType<CmdFrame>().map((f) => f.id).toSet();
      expect(ids, hasLength(2));
    });

    test('an ack for another id is ignored', () {
      fakeAsync((async) {
        final r = Rig();
        AckFrame? got;
        r.session.cmd('desk', const NextCommand()).then((a) => got = a);
        r.session.onFrame(AckFrame.ok('someone-else'));
        async.flushMicrotasks();
        expect(got, isNull);
      });
    });

    test('a failed ack is passed on', () async {
      final r = Rig();
      final future = r.session.cmd('desk', const NextCommand());
      r.session.onFrame(AckFrame.failed(r.lastCmd.id, AckError.nothingPlayable));
      final ack = await future;
      expect(ack.ok, isFalse);
      expect(ack.error, AckError.nothingPlayable);
    });

    test('times out after 11 s with a timeout ack', () {
      fakeAsync((async) {
        final r = Rig();
        AckFrame? got;
        r.session.cmd('desk', const NextCommand()).then((a) => got = a);
        async.elapse(const Duration(seconds: 10, milliseconds: 900));
        expect(got, isNull);
        async.elapse(const Duration(milliseconds: 200));
        expect(got?.error, AckError.timeout);
      });
    });

    test('a late ack after the timeout is harmless', () {
      fakeAsync((async) {
        final r = Rig();
        r.session.cmd('desk', const NextCommand()).ignore();
        final id = r.lastCmd.id;
        async.elapse(const Duration(seconds: 12));
        r.session.onFrame(AckFrame.ok(id));
        async.flushMicrotasks();
      });
    });

    test('an unsendable cmd is offline at once', () async {
      final r = Rig(sends: false);
      final ack = await r.session.cmd('desk', const NextCommand());
      expect(ack.error, AckError.offline);
    });

    test('disconnecting answers everything pending with offline', () async {
      final r = Rig();
      r.session.onFrame(r.welcome());
      final future = r.session.cmd('desk', const NextCommand());
      r.session.onDisconnected();
      expect((await future).error, AckError.offline);
      expect(r.session.isRemote, isFalse);
    });

    test('target commands go to the active device; none means offline', () async {
      final r = Rig();
      expect((await r.session.next()).error, AckError.offline);
      expect(r.sent, isEmpty);
      r.session.onFrame(r.welcome());
      r.session.next().ignore();
      expect(r.lastCmd.to, 'desk');
    });

    test('each transport helper sends the right command', () {
      final r = Rig();
      r.session.onFrame(r.welcome());
      r.session.prev().ignore();
      expect(r.lastCmd.cmd, isA<PrevCommand>());
      r.session.jump('q-1').ignore();
      expect((r.lastCmd.cmd as JumpCommand).uid, 'q-1');
      r.session.volume(0.3).ignore();
      expect((r.lastCmd.cmd as VolumeCommand).value, 0.3);
      r.session.shuffle(true).ignore();
      expect((r.lastCmd.cmd as ShuffleCommand).on, isTrue);
      r.session.repeat(ConnectRepeat.one).ignore();
      expect((r.lastCmd.cmd as RepeatCommand).mode, ConnectRepeat.one);
      r.session.pause().ignore();
      expect(r.lastCmd.cmd, isA<PauseCommand>());
      r.session.resume().ignore();
      expect(r.lastCmd.cmd, isA<ResumeCommand>());
      r.session.seek(5000).ignore();
      expect((r.lastCmd.cmd as SeekCommand).positionMs, 5000);
    });
  });

  group('optimistic overlay', () {
    Rig playingRig() {
      final r = Rig();
      r.session.onFrame(r.welcome(
        states: {'desk': StampedState(state: state(seq: 5, positionMs: 10000), at: r.hubNow)},
      ));
      return r;
    }

    test('pause shows paused at once and freezes the position', () {
      final r = playingRig();
      r.hubNow += 2000;
      r.session.pause().ignore();
      final view = r.session.nowPlaying()!;
      expect(view.playing, isFalse);
      expect(view.positionMs, 12000);
      r.hubNow += 5000;
      expect(r.session.positionMs(), 12000);
    });

    test('resume after pause keeps the frozen position moving again', () {
      final r = playingRig();
      r.session.pause().ignore();
      r.hubNow += 3000;
      r.session.resume().ignore();
      expect(r.session.nowPlaying()!.playing, isTrue);
      expect(r.session.positionMs(), 10000);
      r.hubNow += 1000;
      expect(r.session.positionMs(), 11000);
    });

    test('seek shows the new position and keeps playing from it', () {
      final r = playingRig();
      r.session.seek(90000).ignore();
      expect(r.session.positionMs(), 90000);
      r.hubNow += 1000;
      expect(r.session.positionMs(), 91000);
    });

    test('a newer state ends the overlay', () {
      final r = playingRig();
      r.session.pause().ignore();
      r.stateFrame('desk', state(seq: 6, playing: true, positionMs: 30000));
      final view = r.session.nowPlaying()!;
      expect(view.playing, isTrue);
      expect(view.positionMs, 30000);
    });

    test('an older or equal state does not end the overlay', () {
      final r = playingRig();
      r.session.pause().ignore();
      r.stateFrame('desk', state(seq: 5, playing: true));
      expect(r.session.nowPlaying()!.playing, isFalse);
    });

    test('the overlay lapses after 3 s', () {
      fakeAsync((async) {
        final r = playingRig();
        r.session.pause().ignore();
        expect(r.session.nowPlaying()!.playing, isFalse);
        async.elapse(const Duration(seconds: 3, milliseconds: 100));
        expect(r.session.nowPlaying()!.playing, isTrue);
      });
    });

    test('the overlay notifies listeners when it lapses', () {
      fakeAsync((async) {
        final r = playingRig();
        r.session.pause().ignore();
        var n = 0;
        r.session.addListener(() => n++);
        async.elapse(const Duration(seconds: 4));
        expect(n, 1);
      });
    });

    test('no overlay without a target', () {
      final r = Rig();
      r.session.onFrame(r.welcome(active: self));
      r.session.pause().ignore();
      expect(r.sent, isEmpty);
    });
  });
}
