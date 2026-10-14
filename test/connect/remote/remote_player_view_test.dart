import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/player/remote/remote_player.dart';
import 'package:eq_app/services/connect/connect_protocol.dart';
import 'package:eq_app/services/connect/remote/connect_remote_session.dart';
import 'package:eq_app/widgets/common.dart';

const _self = 'phone';

DeviceInfo _device(String id, DeviceKind kind, {bool player = true}) =>
    DeviceInfo(
      id: id,
      kind: kind,
      name: 'Name of $id',
      platform: null,
      appVersion: null,
      caps: player ? const [ConnectCap.player, ConnectCap.yt] : const [],
      online: true,
      lastSeenAt: '2026-01-01T00:00:00Z',
    );

TrackRef _yt(String id) => YtTrackRef(
      videoId: id,
      title: 't$id',
      artist: 'a$id',
      album: null,
      durationMs: 200000,
      artUrl: null,
    );

class _Rig {
  _Rig({int queued = 5}) {
    session = ConnectRemoteSession(
      selfId: _self,
      send: (frame) {
        sent.add(frame);
        return true;
      },
      hubNowMs: () => hubNow,
    );
    final phone = _device(_self, DeviceKind.mobile);
    final desk = _device('desk', DeviceKind.desktop);
    session.onFrame(WelcomeFrame(
      v: 1,
      deviceId: _self,
      serverTime: hubNow,
      devices: [phone, desk],
      activeDeviceId: 'desk',
      states: const {},
    ));
    session.onFrame(StampedStateFrame(
      deviceId: 'desk',
      state: StampedState(
        at: hubNow,
        state: PlayerState(
          seq: 1,
          track: _yt('now'),
          playing: true,
          positionMs: 10000,
          durationMs: 200000,
          volume: 0.62,
          shuffle: false,
          repeat: ConnectRepeat.off,
          queue: [
            for (var i = 0; i < queued; i++)
              QueueEntry(uid: 'u$i', track: _yt('q$i')),
          ],
        ),
      ),
    ));
  }

  late final ConnectRemoteSession session;
  final sent = <ConnectFrame>[];
  final int hubNow = 1000000;

  CmdFrame get lastCmd => sent.whereType<CmdFrame>().last;
}

Future<void> _pump(
  WidgetTester tester,
  _Rig rig,
  Size size, {
  double bottomPadding = 0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(bottom: bottomPadding);
  tester.view.viewPadding = FakeViewPadding(bottom: bottomPadding);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(),
    home: RemotePlayerView(
      remote: rig.session.nowPlaying()!,
      session: rig.session,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Cancels the session's ack/overlay timers, which the test binding would
/// otherwise report as leaked.
Future<void> _done(WidgetTester tester, _Rig rig) async {
  await tester.pumpWidget(const SizedBox());
  rig.session.dispose();
}

void main() {
  tearDown(() {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.views.first
      ..resetPhysicalSize()
      ..resetDevicePixelRatio()
      ..resetPadding()
      ..resetViewPadding();
  });

  final sizes = <String, (Size, double)>{
    '360x780': (const Size(360, 780), 0),
    '780x360': (const Size(780, 360), 0),
    '640x360': (const Size(640, 360), 0),
    '320x568': (const Size(320, 568), 0),
    '800x1280': (const Size(800, 1280), 0),
    '1280x800': (const Size(1280, 800), 0),
    '360x780 + 44 inset': (const Size(360, 780), 44),
  };

  group('layout', () {
    for (final entry in sizes.entries) {
      final (size, inset) = entry.value;
      final landscape = size.width > size.height;
      testWidgets('${entry.key}: no overflow, one wave', (tester) async {
        final rig = _Rig();
        await _pump(tester, rig, size, bottomPadding: inset);
        expect(tester.takeException(), isNull);
        expect(find.byType(WaveformSeekBar), findsOneWidget);
        expect(find.byType(DraggableScrollableSheet),
            landscape ? findsNothing : findsOneWidget);
      });

      if (landscape) {
        testWidgets('${entry.key}: queue sits right of the art', (tester) async {
          final rig = _Rig();
          await _pump(tester, rig, size);
          final art = tester.getRect(find.byKey(const Key('remote-art')));
          final queue = tester.getRect(find.byKey(const Key('remote-queue')));
          expect(queue.left, greaterThanOrEqualTo(art.right));
          expect(queue.top < art.bottom && art.top < queue.bottom, isTrue);
          if (size.width == 780) expect(art.width, greaterThanOrEqualTo(200));
        });
      }
    }
  });

  group('interactions', () {
    testWidgets('play button sends pause', (tester) async {
      final rig = _Rig();
      await _pump(tester, rig, const Size(360, 780));
      await tester.tap(find.byTooltip('Pause on Name of desk'));
      await tester.pump();
      expect(rig.lastCmd.cmd, isA<PauseCommand>());
      await _done(tester, rig);
    });

    testWidgets('queue row jumps to its uid', (tester) async {
      final rig = _Rig();
      await _pump(tester, rig, const Size(780, 360));
      await tester.tap(find.text('tq1'));
      await tester.pump();
      final cmd = rig.lastCmd.cmd;
      expect(cmd, isA<JumpCommand>());
      expect((cmd as JumpCommand).uid, 'u1');
      await _done(tester, rig);
    });

    testWidgets('tapping the wave right of centre seeks', (tester) async {
      final rig = _Rig();
      await _pump(tester, rig, const Size(360, 780));
      final wave = tester.getRect(find.byType(WaveformSeekBar));
      await tester.tapAt(Offset(wave.center.dx + 60, wave.top + 40));
      await tester.pump();
      expect(rig.lastCmd.cmd, isA<SeekCommand>());
      await _done(tester, rig);
    });

    testWidgets('empty queue shows the empty state', (tester) async {
      final rig = _Rig(queued: 0);
      await _pump(tester, rig, const Size(780, 360));
      expect(find.text('Nothing queued on Name of desk'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
