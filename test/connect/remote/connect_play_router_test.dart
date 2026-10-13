import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'package:eq_app/models/track_extras.dart';
import 'package:eq_app/services/connect/connect_protocol.dart';
import 'package:eq_app/services/connect/remote/connect_play_router.dart';
import 'package:eq_app/services/connect/remote/connect_remote_session.dart';
import 'package:eq_app/services/mixes/daily_mixes.dart';
import 'package:eq_app/services/mixes/mix_track_ref.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';

const me = 'phone';

SongModel song(int id, {String? videoId, String data = '/music/x.mp3'}) =>
    SongModel({
      '_id': id,
      '_data': videoId == null ? data : 'https://music.youtube.com/watch?v=$videoId',
      'title': 'Song $id',
      '_display_name': 'x',
      '_display_name_wo_ext': 'x',
      '_size': 0,
      'is_music': true,
      ...?(videoId == null ? null : {TrackKeys.videoId: videoId}),
    });

YtTrack ytTrack(String id) => YtTrack(videoId: id, title: 'Yt $id');

DeviceInfo dev(String id, {bool online = true}) => DeviceInfo(
      id: id,
      kind: DeviceKind.desktop,
      name: 'Desk',
      platform: null,
      appVersion: null,
      caps: const [ConnectCap.player],
      online: online,
      lastSeenAt: 'x',
    );

class FakeUi implements ConnectPlayUi {
  FakeUi(this.answer);
  bool answer;
  final said = <String>[];
  final asked = <String>[];

  @override
  Future<bool> confirmPlayHere(String title, String deviceName) async {
    asked.add('$title|$deviceName');
    return answer;
  }

  @override
  void say(String message) => said.add(message);
}

class Rig {
  Rig({bool remote = true, bool ackOk = true, AckError? ackError, bool answer = true})
      : ui = FakeUi(answer) {
    session = ConnectRemoteSession(
      selfId: me,
      send: (frame) {
        sent.add(frame);
        if (frame is CmdFrame && autoAck) {
          scheduleMicrotask(() => session.onFrame(
                ackOk ? AckFrame.ok(frame.id) : AckFrame.failed(frame.id, ackError!),
              ));
        }
        return true;
      },
      hubNowMs: () => 1000,
    );
    if (remote) {
      session.onFrame(WelcomeFrame(
        v: 1,
        deviceId: me,
        serverTime: 1000,
        devices: [dev(me), dev('desk')],
        activeDeviceId: 'desk',
        states: const {},
      ));
    }
    ConnectPlayRouter.instance =
        ConnectPlayRouter(session: session, deviceId: me, ui: ui);
  }

  late final ConnectRemoteSession session;
  final FakeUi ui;
  final sent = <ConnectFrame>[];
  bool autoAck = true;

  List<CmdFrame> get cmds => sent.whereType<CmdFrame>().toList();
}

void main() {
  tearDown(() => ConnectPlayRouter.instance = null);

  group('planRemotePlay', () {
    final y1 = ytRef('1');
    final y2 = ytRef('2');
    final loc = LocalTrackRef(
      deviceId: me,
      id: '9',
      title: 'Mine',
      artist: null,
      album: null,
      durationMs: null,
    );
    const other = OtherTrackRef(
      title: 'Radio',
      artist: null,
      album: null,
      durationMs: null,
      artUrl: null,
    );

    test('sends everything from the tapped item', () {
      final plan = planRemotePlay([y1, y2], 1) as SendPlay;
      expect(plan.items, [y2]);
      expect(plan.dropped, 0);
    });

    test('counts and drops what cannot be sent', () {
      final plan = planRemotePlay([y1, loc, y2, other], 0) as SendPlay;
      expect(plan.items, [y1, y2]);
      expect(plan.dropped, 2);
    });

    test('items before the tapped one are not counted', () {
      final plan = planRemotePlay([loc, y1, y2], 1) as SendPlay;
      expect(plan.dropped, 0);
    });

    test('a tapped local song asks, even with sendable songs after it', () {
      final plan = planRemotePlay([loc, y1], 0);
      expect(plan, isA<OnlyHere>());
      expect((plan as OnlyHere).title, 'Mine');
    });

    test('a tapped radio stream asks', () {
      expect(planRemotePlay([other], 0), isA<OnlyHere>());
    });

    test('nothing sendable after the tap asks', () {
      expect(planRemotePlay([y1, loc], 1), isA<OnlyHere>());
    });

    test('a bad index asks rather than throws', () {
      expect(planRemotePlay([y1], 5), isA<OnlyHere>());
      expect(planRemotePlay([], 0), isA<OnlyHere>());
    });

    test('lenient: starts at the first sendable', () {
      final plan = planRemotePlay([loc, y1, other, y2], 0,
          startAtFirstPlayable: true) as SendPlay;
      expect(plan.items, [y1, y2]);
      expect(plan.dropped, 2);
    });

    test('lenient with nothing sendable asks', () {
      expect(
        planRemotePlay([loc, other], 0, startAtFirstPlayable: true),
        isA<OnlyHere>(),
      );
    });
  });

  group('routing', () {
    test('returns null when not in remote mode', () {
      Rig(remote: false);
      expect(
        ConnectPlayRouter.songs([song(1, videoId: 'a')], 0, here: () async {}),
        isNull,
      );
    });

    test('returns null with no router at all', () {
      ConnectPlayRouter.instance = null;
      expect(
        ConnectPlayRouter.songs([song(1, videoId: 'a')], 0, here: () async {}),
        isNull,
      );
    });

    test('inside local() nothing is rerouted', () {
      Rig();
      final routed = ConnectPlayRouter.local(
        () => ConnectPlayRouter.songs(
          [song(1, videoId: 'a')],
          0,
          here: () async {},
        ),
      );
      expect(routed, isNull);
    });

    test('local() holds across awaits', () async {
      Rig();
      Object? seen = 'unset';
      await ConnectPlayRouter.local(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        seen = ConnectPlayRouter.target;
      });
      expect(seen, isNull);
    });

    test('target is the remote device outside local()', () {
      Rig();
      expect(ConnectPlayRouter.target?.id, 'desk');
    });

    test('songs: sends a play cmd for YouTube songs and does not play here',
        () async {
      final r = Rig();
      var local = 0;
      await ConnectPlayRouter.songs(
        [song(1, videoId: 'a'), song(2, videoId: 'b')],
        1,
        here: () async => local++,
      );
      expect(local, 0);
      final cmd = r.cmds.single;
      expect(cmd.to, 'desk');
      final play = cmd.cmd as PlayCommand;
      expect(play.index, 0);
      expect((play.items.single as YtTrackRef).videoId, 'b');
      expect(play.radio, isNull);
      expect(r.ui.said, isEmpty);
    });

    test('songs: radio flag is carried', () async {
      final r = Rig();
      await ConnectPlayRouter.songs(
        [song(1, videoId: 'a')],
        0,
        radio: true,
        here: () async {},
      );
      expect((r.cmds.single.cmd as PlayCommand).radio, isTrue);
    });

    test('songs: a tapped local song asks and plays here on yes', () async {
      final r = Rig();
      DeviceInfo? targetInside = dev('sentinel');
      await ConnectPlayRouter.songs([song(7)], 0, here: () async {
        targetInside = ConnectPlayRouter.target;
      });
      expect(r.ui.asked, ['Song 7|Desk']);
      expect(r.cmds, isEmpty);
      expect(targetInside, isNull, reason: 'the local play must not reroute');
    });

    test('songs: no means nothing happens', () async {
      final r = Rig(answer: false);
      var local = 0;
      await ConnectPlayRouter.songs([song(7)], 0, here: () async => local++);
      expect(local, 0);
      expect(r.cmds, isEmpty);
    });

    test('songs: tells how many stayed behind', () async {
      final r = Rig();
      await ConnectPlayRouter.songs(
        [song(1, videoId: 'a'), song(2), song(3), song(4, videoId: 'd')],
        0,
        here: () async {},
      );
      expect((r.cmds.single.cmd as PlayCommand).items, hasLength(2));
      expect(r.ui.said, ['2 songs stayed on this phone.']);
    });

    test('songs: singular wording', () async {
      final r = Rig();
      await ConnectPlayRouter.songs(
        [song(1, videoId: 'a'), song(2)],
        0,
        here: () async {},
      );
      expect(r.ui.said, ['1 song stayed on this phone.']);
    });

    test('a refused play is explained and not played here', () async {
      final r = Rig(ackOk: false, ackError: AckError.nothingPlayable);
      var local = 0;
      await ConnectPlayRouter.yt([ytTrack('a')], 0, here: () async => local++);
      expect(local, 0);
      expect(r.ui.said.single, 'Desk could not play that.');
    });

    test('yt: radio and index', () async {
      final r = Rig();
      await ConnectPlayRouter.yt(
        [ytTrack('a'), ytTrack('b')],
        1,
        radio: true,
        here: () async {},
      );
      final play = r.cmds.single.cmd as PlayCommand;
      expect((play.items.single as YtTrackRef).videoId, 'b');
      expect(play.radio, isTrue);
    });

    test('mix: sends the YouTube tracks, starts at the first playable',
        () async {
      final r = Rig();
      await ConnectPlayRouter.mix([
        MixTrackRef.local(song(1)),
        MixTrackRef.youtube(ytTrack('a')),
        MixTrackRef.youtube(ytTrack('b')),
      ], here: () async {});
      final play = r.cmds.single.cmd as PlayCommand;
      expect(play.items.map((i) => (i as YtTrackRef).videoId), ['a', 'b']);
      expect(r.ui.said, ['1 song stayed on this phone.']);
    });

    test('mix with nothing sendable offers to play here', () async {
      final r = Rig();
      var local = 0;
      await ConnectPlayRouter.mix([MixTrackRef.local(song(1))],
          here: () async => local++);
      expect(r.ui.asked, hasLength(1));
      expect(local, 1);
    });

    test('enqueue sends and confirms', () async {
      final r = Rig();
      await ConnectPlayRouter.enqueueYt([ytTrack('a')], EnqueueMode.next);
      final cmd = r.cmds.single.cmd as EnqueueCommand;
      expect(cmd.mode, EnqueueMode.next);
      expect(r.ui.said.single, 'Playing next on Desk.');
    });

    test('enqueue reports what stayed behind', () async {
      final r = Rig();
      await ConnectPlayRouter.enqueueSongs(
        [song(1, videoId: 'a'), song(2)],
        EnqueueMode.end,
      );
      expect(r.ui.said.single,
          'Added to the queue on Desk. 1 song stayed on this phone.');
    });

    test('enqueue of a local song says why not', () async {
      final r = Rig();
      await ConnectPlayRouter.enqueueSongs([song(3)], EnqueueMode.end);
      expect(r.cmds, isEmpty);
      expect(r.ui.said.single, contains('only on this phone'));
    });

    test('enqueue returns null when not remote', () {
      Rig(remote: false);
      expect(ConnectPlayRouter.enqueueYt([ytTrack('a')], EnqueueMode.end), isNull);
    });
  });

  group('failure wording', () {
    test('every error reads as a sentence naming the device', () {
      for (final e in [...AckError.values, null]) {
        expect(ConnectPlayRouter.failureMessage(e, 'Desk'), contains('Desk'));
      }
    });
  });
}

TrackRef ytRef(String id) => YtTrackRef(
      videoId: id,
      title: 'Yt $id',
      artist: null,
      album: null,
      durationMs: null,
      artUrl: null,
    );
