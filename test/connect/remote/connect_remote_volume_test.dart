import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/services/connect/connect_protocol.dart';
import 'package:eq_app/services/connect/remote/connect_remote_session.dart';

const _self = 'phone';

DeviceInfo _device(String id, DeviceKind kind) => DeviceInfo(
      id: id,
      kind: kind,
      name: 'Name of $id',
      platform: null,
      appVersion: null,
      caps: const [ConnectCap.player],
      online: true,
      lastSeenAt: '2026-01-01T00:00:00Z',
    );

PlayerState _state(int seq, double volume) => PlayerState(
      seq: seq,
      track: null,
      playing: false,
      positionMs: 0,
      durationMs: null,
      volume: volume,
      shuffle: false,
      repeat: ConnectRepeat.off,
      queue: const [],
    );

class _Rig {
  _Rig({double? volume}) {
    session = ConnectRemoteSession(
      selfId: _self,
      send: (frame) {
        sent.add(frame);
        return true;
      },
      hubNowMs: () => 1000000,
    );
    session.onFrame(WelcomeFrame(
      v: 1,
      deviceId: _self,
      serverTime: 1000000,
      devices: [_device(_self, DeviceKind.mobile), _device('desk', DeviceKind.desktop)],
      activeDeviceId: 'desk',
      states: {
        if (volume != null)
          'desk': StampedState(state: _state(1, volume), at: 1000000),
      },
    ));
  }

  late final ConnectRemoteSession session;
  final sent = <ConnectFrame>[];
  int seq = 1;

  List<double> get volumesSent => [
        for (final f in sent.whereType<CmdFrame>())
          if (f.cmd is VolumeCommand) (f.cmd as VolumeCommand).value,
      ];

  void report(double volume) => session.onFrame(StampedStateFrame(
        deviceId: 'desk',
        state: StampedState(state: _state(++seq, volume), at: 1000000),
      ));

  double get shown => session.nowPlaying()!.volume;
}

void _scenario(void Function(FakeAsync async) body) {
  fakeAsync((async) => withClock(async.getClock(DateTime.utc(2026, 10, 15)), () => body(async)));
}

void main() {
  group('nudgeVolume', () {
    test('steps by 0.05 and rounds to two decimals', () {
      _scenario((async) {
        final r = _Rig(volume: 0.3);
        expect(r.session.nudgeVolume(1), 0.35);
        async.elapse(const Duration(milliseconds: 200));
        expect(r.session.nudgeVolume(-1), 0.3);
        expect(r.session.nudgeVolume(-1), 0.25);
      });
    });

    test('is null outside remote mode', () {
      _scenario((async) {
        final r = _Rig(volume: 0.3);
        r.session.onFrame(DevicesFrame(
          devices: [_device(_self, DeviceKind.mobile), _device('desk', DeviceKind.desktop)],
          activeDeviceId: _self,
        ));
        expect(r.session.nudgeVolume(1), isNull);
        expect(r.volumesSent, isEmpty);
      });
    });

    test('clamps, and sends nothing when already at a bound', () {
      _scenario((async) {
        final r = _Rig(volume: 1.0);
        expect(r.session.nudgeVolume(1), 1.0);
        expect(r.volumesSent, isEmpty);
        final low = _Rig(volume: 0.02);
        expect(low.session.nudgeVolume(-1), 0.0);
        expect(low.volumesSent, [0.0]);
        async.elapse(const Duration(seconds: 1));
        expect(low.session.nudgeVolume(-1), 0.0);
        expect(low.volumesSent, [0.0]);
      });
    });

    test('sends at once, then one trailing send of the latest value', () {
      _scenario((async) {
        final r = _Rig(volume: 0.5);
        r.session.nudgeVolume(1);
        expect(r.volumesSent, [0.55]);
        r.session.nudgeVolume(1);
        r.session.nudgeVolume(1);
        r.session.nudgeVolume(1);
        expect(r.volumesSent, [0.55]);
        async.elapse(const Duration(milliseconds: 119));
        expect(r.volumesSent, [0.55]);
        async.elapse(const Duration(milliseconds: 2));
        expect(r.volumesSent, [0.55, 0.7]);
        // Idle for a while: the next press goes out immediately again.
        async.elapse(const Duration(seconds: 1));
        r.session.nudgeVolume(-1);
        expect(r.volumesSent, [0.55, 0.7, 0.65]);
      });
    });

    test('dispose cancels the trailing send', () {
      _scenario((async) {
        final r = _Rig(volume: 0.5);
        r.session.nudgeVolume(1);
        r.session.nudgeVolume(1);
        r.session.dispose();
        async.elapse(const Duration(seconds: 1));
        expect(r.volumesSent, [0.55]);
      });
    });
  });

  group('volume overlay', () {
    test('shows the guess at once, also for a slider volume()', () {
      _scenario((async) {
        final r = _Rig(volume: 0.5);
        r.session.volume(0.8).ignore();
        expect(r.shown, 0.8);
      });
    });

    test('survives a stale echo, drops once the device reports it', () {
      _scenario((async) {
        final r = _Rig(volume: 0.5);
        r.session.nudgeVolume(1);
        async.elapse(const Duration(milliseconds: 200));
        r.session.nudgeVolume(1);
        expect(r.shown, 0.6);
        r.report(0.55); // the echo of the first step
        expect(r.shown, 0.6);
        r.report(0.595); // within 0.01 of the guess
        expect(r.shown, 0.595);
        r.report(0.4);
        expect(r.shown, 0.4);
      });
    });

    test('lapses after the TTL since the last change', () {
      _scenario((async) {
        final r = _Rig(volume: 0.5);
        var notified = 0;
        r.session.addListener(() => notified++);
        r.session.nudgeVolume(1);
        async.elapse(const Duration(seconds: 2));
        r.session.nudgeVolume(1);
        async.elapse(const Duration(milliseconds: 2500));
        expect(r.shown, 0.6, reason: 'the TTL restarted with the second press');
        final before = notified;
        async.elapse(const Duration(milliseconds: 600));
        expect(r.shown, 0.5);
        expect(notified, greaterThan(before));
      });
    });

    test('a state that ends the transport overlay leaves the volume one alone', () {
      _scenario((async) {
        final r = _Rig(volume: 0.5);
        r.session.pause().ignore();
        r.session.nudgeVolume(1);
        r.report(0.5);
        expect(r.session.nowPlaying()!.playing, isFalse, reason: 'state says paused anyway');
        expect(r.shown, 0.55);
      });
    });
  });
}
