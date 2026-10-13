import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'package:eq_app/models/track_extras.dart';
import 'package:eq_app/services/connect/connect_protocol.dart';
import 'package:eq_app/services/connect/connect_state_publisher.dart';
import 'package:eq_app/services/connect/remote/connect_link_direction.dart';
import 'package:eq_app/services/connect/remote/connect_remote_session.dart';
import 'package:eq_app/services/connect/remote/connect_transfer.dart';

const me = 'phone';

DeviceInfo dev(
  String id, {
  DeviceKind kind = DeviceKind.desktop,
  String name = 'Studio Mac',
  bool online = true,
  String seen = '2026-01-01T00:00:00Z',
  bool player = true,
}) =>
    DeviceInfo(
      id: id,
      kind: kind,
      name: name,
      platform: null,
      appVersion: null,
      caps: player ? const [ConnectCap.player] : const [],
      online: online,
      lastSeenAt: seen,
    );

SongModel ytSong() => SongModel({
      '_id': 1,
      '_data': 'https://music.youtube.com/watch?v=x',
      'title': 'S',
      '_display_name': 'x',
      '_display_name_wo_ext': 'x',
      '_size': 0,
      'is_music': true,
      TrackKeys.videoId: 'x',
    });

class Src implements ConnectStateSource {
  bool playing = false;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  ConnectSnapshot read() => ConnectSnapshot(
        track: playing ? ytSong() : null,
        playing: playing,
        position: const Duration(seconds: 5),
        duration: null,
        volume: 1,
        shuffle: false,
        repeat: ConnectRepeat.off,
        upcoming: const [],
      );
}

class Rig {
  Rig() {
    session = ConnectRemoteSession(
      selfId: me,
      send: (f) {
        sent.add(f);
        if (f is CmdFrame) {
          scheduleMicrotask(() => session.onFrame(AckFrame.ok(f.id)));
        }
        return true;
      },
      hubNowMs: () => 1000,
    );
    transfer = ConnectTransfer(
      session: session,
      selfId: me,
      localState: src,
      pauseLocal: () async => paused++,
      playLocal: (c) async => AckFrame.ok('l'),
      select: (id) {
        selects.add(id);
        return true;
      },
      nameOf: (id) => id,
    );
    direction = ConnectLinkDirection(
      session: session,
      transfer: transfer,
      selfId: me,
      phonePlaying: () => src.playing,
      isOnline: () => online,
      select: (id) {
        selects.add(id);
        return true;
      },
    );
  }

  late final ConnectRemoteSession session;
  late final ConnectTransfer transfer;
  late final ConnectLinkDirection direction;
  final src = Src();
  final sent = <ConnectFrame>[];
  final selects = <String?>[];
  int paused = 0;
  bool online = true;

  void list(List<DeviceInfo> devices, {String? active, Map<String, StampedState> states = const {}}) {
    session.onFrame(WelcomeFrame(
      v: 1,
      deviceId: me,
      serverTime: 1000,
      devices: devices,
      activeDeviceId: active,
      states: states,
    ));
  }

  StampedState playingState() => StampedState(
        state: PlayerState(
          seq: 1,
          track: YtTrackRef(videoId: 'd', title: 'D', artist: null, album: null, durationMs: null, artUrl: null),
          playing: true,
          positionMs: 0,
          durationMs: null,
          volume: 1,
          shuffle: false,
          repeat: ConnectRepeat.off,
          queue: const [],
        ),
        at: 1000,
      );
}

void main() {
  final phone = dev(me, kind: DeviceKind.mobile, name: 'Pixel');

  group('preselect', () {
    test('the desktop by default', () {
      expect(preselectedChoice(phonePlaying: false, desktopPlaying: false), LinkChoice.desktop);
    });
    test('the phone when it is the one playing', () {
      expect(preselectedChoice(phonePlaying: true, desktopPlaying: false), LinkChoice.phone);
    });
    test('the desktop when it is the one playing', () {
      expect(preselectedChoice(phonePlaying: false, desktopPlaying: true), LinkChoice.desktop);
    });
    test('the phone when both play', () {
      expect(preselectedChoice(phonePlaying: true, desktopPlaying: true), LinkChoice.phone);
    });
  });

  group('findDesktop', () {
    test('matches kind, name, online and player', () {
      final r = Rig();
      r.list([
        phone,
        dev('other-name', name: 'Else'),
        dev('web', kind: DeviceKind.web, player: true),
        dev('desktop-no-player', player: false),
        dev('off', online: false),
        dev('ok'),
      ]);
      expect(r.direction.findDesktop('Studio Mac')?.id, 'ok');
    });

    test('prefers the most recently seen of equal names', () {
      final r = Rig();
      r.list([
        phone,
        dev('old', seen: '2026-01-01T00:00:00Z'),
        dev('new', seen: '2026-02-01T00:00:00Z'),
      ]);
      expect(r.direction.findDesktop('Studio Mac')?.id, 'new');
    });

    test('null when absent', () {
      final r = Rig();
      r.list([phone]);
      expect(r.direction.findDesktop('Studio Mac'), isNull);
    });
  });

  group('waitForDesktop', () {
    test('returns at once when both are online', () async {
      final r = Rig();
      r.list([phone, dev('desk')]);
      expect((await r.direction.waitForDesktop('Studio Mac'))?.id, 'desk');
    });

    test('waits for the desktop to appear', () {
      fakeAsync((async) {
        final r = Rig();
        r.list([phone]);
        DeviceInfo? got;
        var done = false;
        r.direction.waitForDesktop('Studio Mac').then((d) {
          got = d;
          done = true;
        });
        async.elapse(const Duration(seconds: 5));
        expect(done, isFalse);
        r.session.onFrame(DevicesFrame(devices: [phone, dev('desk')], activeDeviceId: null));
        async.flushMicrotasks();
        expect(got?.id, 'desk');
      });
    });

    test('waits for this phone to be online too', () {
      fakeAsync((async) {
        final r = Rig();
        r.list([dev('desk')]); // phone not listed yet (reconnecting)
        DeviceInfo? got;
        r.direction.waitForDesktop('Studio Mac').then((d) => got = d);
        async.elapse(const Duration(seconds: 2));
        expect(got, isNull);
        r.session.onFrame(DevicesFrame(devices: [phone, dev('desk')], activeDeviceId: null));
        async.flushMicrotasks();
        expect(got?.id, 'desk');
      });
    });

    test('waits for the socket', () {
      fakeAsync((async) {
        final r = Rig();
        r.online = false;
        r.list([phone, dev('desk')]);
        DeviceInfo? got;
        var done = false;
        r.direction.waitForDesktop('Studio Mac').then((d) {
          got = d;
          done = true;
        });
        async.elapse(const Duration(seconds: 3));
        expect(done, isFalse);
        r.online = true;
        r.session.onFrame(DevicesFrame(devices: [phone, dev('desk')], activeDeviceId: null));
        async.flushMicrotasks();
        expect(got?.id, 'desk');
      });
    });

    test('gives up after 20 s with null', () {
      fakeAsync((async) {
        final r = Rig();
        r.list([phone]);
        var done = false;
        DeviceInfo? got = dev('sentinel');
        r.direction.waitForDesktop('Studio Mac').then((d) {
          got = d;
          done = true;
        });
        async.elapse(const Duration(seconds: 19, milliseconds: 900));
        expect(done, isFalse);
        async.elapse(const Duration(milliseconds: 200));
        expect(done, isTrue);
        expect(got, isNull);
      });
    });

    test('a late desktop after the timeout changes nothing', () {
      fakeAsync((async) {
        final r = Rig();
        r.list([phone]);
        r.direction.waitForDesktop('Studio Mac');
        async.elapse(const Duration(seconds: 21));
        r.session.onFrame(DevicesFrame(devices: [phone, dev('desk')], activeDeviceId: null));
        async.flushMicrotasks();
      });
    });
  });

  group('apply', () {
    test('chosen device already playing: just select it', () async {
      final r = Rig();
      r.list([phone, dev('desk')], states: {'desk': StampedState(
          state: PlayerState(seq: 1, track: null, playing: true, positionMs: 0, durationMs: null, volume: 1, shuffle: false, repeat: ConnectRepeat.off, queue: const []),
          at: 1000)});
      final result = await r.direction.apply(LinkChoice.desktop, dev('desk'));
      expect(result.ok, isTrue);
      expect(r.selects, ['desk']);
      expect(r.sent, isEmpty);
    });

    test('nothing playing: just select the choice', () async {
      final r = Rig();
      r.list([phone, dev('desk')]);
      await r.direction.apply(LinkChoice.phone, dev('desk'));
      expect(r.selects, [me]);
      expect(r.sent, isEmpty);
    });

    test('phone playing, desktop chosen: transfer phone -> desktop', () async {
      final r = Rig();
      r.src.playing = true;
      r.list([phone, dev('desk')]);
      final result = await r.direction.apply(LinkChoice.desktop, dev('desk'));
      expect(result.ok, isTrue);
      final cmd = r.sent.whereType<CmdFrame>().single;
      expect(cmd.to, 'desk');
      expect(cmd.cmd, isA<PlayCommand>());
      expect(r.paused, 1);
      expect(r.selects, ['desk']);
    });

    test('desktop playing, phone chosen: transfer desktop -> phone', () async {
      final r = Rig();
      r.list([phone, dev('desk')], states: {'desk': r.playingState()});
      final result = await r.direction.apply(LinkChoice.phone, dev('desk'));
      expect(result.ok, isTrue);
      final cmd = r.sent.whereType<CmdFrame>().single;
      expect(cmd.to, 'desk');
      expect(cmd.cmd, isA<PauseCommand>());
    });

    test('both playing, either choice: just select it', () async {
      final r = Rig();
      r.src.playing = true;
      r.list([phone, dev('desk')], states: {'desk': r.playingState()});
      await r.direction.apply(LinkChoice.desktop, dev('desk'));
      expect(r.selects, ['desk']);
      expect(r.sent, isEmpty);
    });
  });
}
