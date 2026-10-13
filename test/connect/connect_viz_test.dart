import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:eq_app/services/connect/connect_protocol.dart';
import 'package:eq_app/services/connect/connect_viz.dart';
import 'package:eq_app/visualizers/beat_frame.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List db(Iterable<num> values) =>
    Float32List.fromList([for (final v in values) v.toDouble()]);

/// 64 native bands all at [level] dBFS.
Float32List flat(double level, [int n = 64]) =>
    Float32List.fromList(List.filled(n, level));

BeatFrame frame({
  Float32List? bands,
  Float32List? hops,
  int? heardAtUs,
  double sampleRate = 44100,
}) =>
    BeatFrame(
      sampleRate: sampleRate,
      hopSeconds: 256 / 44100,
      synced: heardAtUs != null,
      hops: hops ?? Float32List(0),
      bandsDb: bands ?? flat(-40),
      heardAtUs: heardAtUs,
    );

/// A feed that counts how many listeners are attached, like the native tap
/// being on.
class FakeFeed implements ConnectVizFeed {
  final StreamController<BeatFrame> _c = StreamController<BeatFrame>.broadcast(
    sync: true,
  );
  int listens = 0;
  int cancels = 0;

  @override
  Stream<BeatFrame> get frames {
    final controller = StreamController<BeatFrame>(
      sync: true,
      onListen: () => listens++,
      onCancel: () => cancels++,
    );
    StreamSubscription<BeatFrame>? inner;
    controller.onListen = () {
      listens++;
      inner = _c.stream.listen(controller.add);
    };
    controller.onCancel = () {
      cancels++;
      return inner?.cancel();
    };
    return controller.stream;
  }

  bool get tapOn => listens > cancels;
  void emit(BeatFrame f) => _c.add(f);
}

class Rig {
  Rig({this.playing = true, Duration? interval, Duration? minGap}) {
    streamer = ConnectVizStreamer(
      feed: feed,
      send: (f) {
        if (!accept) return false;
        sent.add(f);
        return true;
      },
      isPlaying: () => playing,
      position: () => Duration(milliseconds: positionMs),
      hubNowMs: () => hubNow,
      nowUs: () => nowUs,
      interval: interval ?? const Duration(milliseconds: 50),
      minGap: minGap ?? const Duration(milliseconds: 25),
    );
  }

  final feed = FakeFeed();
  late final ConnectVizStreamer streamer;
  final sent = <VizFrame>[];
  bool playing;
  bool accept = true;
  int positionMs = 61400;
  int hubNow = 1760295600000;
  int nowUs = 5000000000;

  void live() {
    streamer
      ..setOnline(true)
      ..setSubscribed(true);
  }

  /// Emits a frame [ms] after the previous one.
  void tick(int ms, [BeatFrame? f]) {
    nowUs += ms * 1000;
    hubNow += ms;
    feed.emit(f ?? frame());
  }
}

void main() {
  group('vizUnit', () {
    test('-80 dBFS is 0, 0 dBFS is 1, linear between', () {
      expect(vizUnit(-80), 0);
      expect(vizUnit(0), 1);
      expect(vizUnit(-40), closeTo(0.5, 1e-12));
      expect(vizUnit(-20), closeTo(0.75, 1e-12));
    });

    test('clamps outside the range and survives NaN and infinities', () {
      expect(vizUnit(-200), 0);
      expect(vizUnit(12), 1);
      expect(vizUnit(double.nan), 0);
      expect(vizUnit(double.negativeInfinity), 0);
      expect(vizUnit(double.infinity), 1);
    });
  });

  group('vizBands', () {
    test('always exactly 32 values in 0..1', () {
      for (final n in [64, 40, 1]) {
        final bands = vizBands(flat(-30, n), 44100);
        expect(bands, hasLength(32));
        expect(bands.every((b) => b >= 0 && b <= 1), isTrue);
      }
      expect(vizBands(Float32List(0), 44100), List.filled(32, 0.0));
    });

    test('a flat spectrum maps to one flat level', () {
      final bands = vizBands(flat(-40), 44100);
      expect(bands.every((b) => b == 0.5), isTrue);
    });

    test('low stays first: a bass-only spectrum lights the low bands only', () {
      // Native band centres rise with the index; make the lowest ones loud.
      final native = flat(-80);
      for (var i = 0; i < 6; i++) {
        native[i] = 0;
      }
      final bands = vizBands(native, 44100);
      expect(bands.first, greaterThan(0.9));
      expect(bands.last, 0);
      final firstQuiet = bands.indexWhere((b) => b < 0.1);
      expect(firstQuiet, greaterThan(0));
      expect(bands.sublist(firstQuiet).every((b) => b < 0.1), isTrue);
    });

    test('a treble-only spectrum lights the high bands only', () {
      final native = flat(-80);
      for (var i = 47; i < 53; i++) {
        native[i] = 0;
      }
      final bands = vizBands(native, 44100);
      expect(bands.first, 0);
      expect(bands[30], greaterThan(0.9));
      expect(bands.sublist(0, 20).every((b) => b == 0), isTrue);
    });

    test('a target band takes the LOUDEST native band inside it', () {
      final native = flat(-70);
      // 64 native bands: the top ones (centres ~8-20 kHz) are wide; make one
      // loud and one quiet in the same stretch.
      native[50] = -10;
      final bands = vizBands(native, 44100);
      expect(bands.reduce(math.max), closeTo(vizUnit(-10), 0.011));
    });

    test('values are rounded to 2 decimals', () {
      final bands = vizBands(flat(-33.3333), 44100);
      for (final b in bands) {
        expect((b * 100).roundToDouble(), closeTo(b * 100, 1e-9));
      }
    });

    test('centres of native bands rise and span the audible range', () {
      final c = nativeBandCentres(64, 44100);
      expect(c.first, closeTo(32.3, 0.5));
      expect(c.last, greaterThan(20000));
      for (var i = 1; i < c.length; i++) {
        expect(c[i], greaterThan(c[i - 1]));
      }
    });
  });

  group('vizLevel', () {
    test('silence is 0, full scale everywhere is 1', () {
      expect(vizLevel(flat(-120)), 0);
      expect(vizLevel(flat(0)), 1);
    });

    test('a flat spectrum has the level of its bands', () {
      expect(vizLevel(flat(-40)), 0.5);
    });

    test('one loud band among quiet ones counts for its share of the power',
        () {
      final native = flat(-90);
      native[0] = -10; // mean power ~ -10 - 18 = -28 dB
      expect(vizLevel(native), closeTo(vizUnit(-10 - 10 * math.log(64) / math.ln10), 0.011));
    });

    test('empty is 0', () => expect(vizLevel(Float32List(0)), 0));
  });

  group('streaming rules', () {
    test('nothing is listened to until subscribed AND online AND playing', () {
      final r = Rig();
      expect(r.feed.tapOn, isFalse);
      r.streamer.setSubscribed(true); // not online: stale, ignored
      expect(r.feed.tapOn, isFalse);
      r.streamer.setOnline(true);
      expect(r.feed.tapOn, isFalse, reason: 'a subscription needs a socket');
      r.streamer.setSubscribed(true);
      expect(r.feed.tapOn, isTrue);
    });

    test('a paused player is not analysed even when subscribed', () {
      final r = Rig(playing: false);
      r.live();
      expect(r.feed.tapOn, isFalse);
      r.playing = true;
      r.streamer.refresh();
      expect(r.feed.tapOn, isTrue);
    });

    test('pause releases the native stream; resume takes it again', () {
      final r = Rig();
      r.live();
      expect(r.feed.listens, 1);
      r.playing = false;
      r.streamer.refresh();
      expect(r.feed.tapOn, isFalse);
      expect(r.feed.cancels, 1);
      r.playing = true;
      r.streamer.refresh();
      expect(r.feed.listens, 2);
      expect(r.feed.tapOn, isTrue);
    });

    test('viz_sub off releases it', () {
      final r = Rig();
      r.live();
      r.streamer.setSubscribed(false);
      expect(r.feed.tapOn, isFalse);
    });

    test('disconnect releases it and forgets the subscription', () {
      final r = Rig();
      r.live();
      r.streamer.setOnline(false);
      expect(r.feed.tapOn, isFalse);
      // Back online without a fresh viz_sub from the hub: still off.
      r.streamer.setOnline(true);
      expect(r.feed.tapOn, isFalse);
    });

    test('refresh while already streaming does not stack listeners', () {
      final r = Rig();
      r.live();
      r.streamer.refresh();
      r.streamer.refresh();
      expect(r.feed.listens, 1);
    });

    test('no frames are sent while off', () {
      final r = Rig();
      r.streamer.setOnline(true);
      r.tick(60);
      expect(r.sent, isEmpty);
    });

    test('dispose releases', () {
      final r = Rig();
      r.live();
      r.streamer.dispose();
      expect(r.feed.tapOn, isFalse);
    });
  });

  group('the frame', () {
    test('carries 32 bands, level, beat, position and stays under 1 KiB', () {
      final r = Rig();
      r.live();
      r.tick(60, frame(bands: flat(-33.3333)));
      final f = r.sent.single;
      expect(f.deviceId, isNull);
      expect(f.frame.bands, hasLength(32));
      expect(f.frame.level, 0.58);
      expect(f.frame.beat, 0);
      expect(f.frame.positionMs, 61400);
      expect(utf8.encode(f.encode()).length, lessThan(1024));
    });

    test('heardAt converts the native monotonic time to hub time', () {
      final r = Rig();
      r.live();
      r.tick(60); // first frame
      r.sent.clear();
      // The audio is heard 200 ms after "now" on the monotonic clock.
      r.nowUs += 50000;
      r.hubNow += 50;
      r.feed.emit(frame(heardAtUs: r.nowUs + 200000));
      final f = r.sent.single.frame;
      expect(f.heardAt, r.hubNow + 200);
      // The audio is 200 ms ahead of the playhead, and so is its position.
      expect(f.positionMs, 61400 + 200);
    });

    test('a heard-at in the past is not added to the position', () {
      final r = Rig();
      r.live();
      r.tick(60, frame(heardAtUs: r.nowUs + 60000 - 30000));
      final f = r.sent.single.frame;
      expect(f.heardAt, r.hubNow - 30);
      expect(f.positionMs, 61400);
    });

    test('without a playback clock heardAt is the hub time now', () {
      final r = Rig();
      r.live();
      r.tick(60);
      expect(r.sent.single.frame.heardAt, r.hubNow);
    });

    test('hub clock offset is honoured', () {
      final r = Rig();
      r.live();
      r.hubNow += 7777; // the hub is ahead of the local clock
      r.tick(60, frame(heardAtUs: r.nowUs + 60000 + 100000));
      expect(r.sent.single.frame.heardAt, r.hubNow + 100);
    });

    test('a frame with no bands (iOS) still goes, flat, with a bass level', () {
      final r = Rig();
      r.live();
      r.tick(60, frame(bands: Float32List(0)));
      final f = r.sent.single.frame;
      expect(f.bands, List.filled(32, 0.0));
    });

    test('a refused send (socket gone) is not counted as sent', () {
      final r = Rig();
      r.live();
      r.accept = false;
      r.tick(60);
      expect(r.sent, isEmpty);
      r.accept = true;
      r.tick(5);
      expect(r.sent, hasLength(1), reason: 'the next frame is not held back');
    });
  });

  group('beat', () {
    /// Hops of low-band energy: silence, then a loud kick.
    Float32List quiet() => Float32List.fromList(List.filled(8, 1e-9));
    Float32List kick() => Float32List.fromList(List.filled(8, 0.05));

    Rig warmed() {
      final r = Rig();
      r.live();
      // Establish a quiet floor (sent frames carry beat 0).
      for (var i = 0; i < 30; i++) {
        r.tick(34, frame(hops: Float32List.fromList(List.filled(8, 0.001))));
      }
      return r;
    }

    test('0 when there is no onset', () {
      final r = warmed();
      expect(r.sent.every((f) => f.frame.beat == 0), isTrue);
      expect(r.sent, isNotEmpty);
    });

    test('an onset is reported with its strength, then back to 0', () {
      final r = warmed();
      r.sent.clear();
      // Loud kick (+34 dB over the floor).
      r.tick(34, frame(hops: kick()));
      r.tick(34, frame(hops: kick()));
      final beats = r.sent.map((f) => f.frame.beat).toList();
      expect(beats.reduce(math.max), greaterThan(0.15));
      expect(beats.reduce(math.max), lessThanOrEqualTo(1));
      r.sent.clear();
      for (var i = 0; i < 12; i++) {
        r.tick(34, frame(hops: quiet()));
      }
      expect(r.sent.last.frame.beat, 0);
    });

    test('an onset is sent immediately, not at the next 50 ms slot', () {
      final r = warmed();
      // Make sure the next regular slot is not yet due: send one, then onset.
      r.tick(50, frame(hops: Float32List.fromList(List.filled(8, 0.001))));
      r.sent.clear();
      r.tick(36, frame(hops: kick())); // 36 ms later: past minGap, before 50
      expect(r.sent, hasLength(1));
      expect(r.sent.single.frame.beat, greaterThan(0));
    });

    test('a hit in a frame that was skipped is carried to the next sent', () {
      final r = Rig();
      r.live();
      final floor = Float32List.fromList(List.filled(8, 0.001));
      for (var i = 0; i < 30; i++) {
        r.tick(34, frame(hops: floor));
      }
      // Tick until a frame goes out, so the next tick is inside minGap.
      var before = r.sent.length;
      while (r.sent.length == before) {
        r.tick(10, frame(hops: floor));
      }
      r.sent.clear();
      r.tick(10, frame(hops: kick()));
      expect(r.sent, isEmpty, reason: 'only 10 ms since the last frame');
      expect(r.streamer.debugPendingBeat, greaterThan(0));
      // ...and reported on the next frame that goes out.
      before = r.sent.length;
      while (r.sent.length == before) {
        r.tick(10, frame(hops: floor));
      }
      expect(r.sent.first.frame.beat, greaterThan(0));
    });
  });

  group('throttling', () {
    test('30 Hz input comes out at about 20 fps', () {
      final r = Rig();
      r.live();
      for (var i = 0; i < 300; i++) {
        r.tick(33);
      }
      final seconds = 300 * 33 / 1000;
      final fps = r.sent.length / seconds;
      expect(fps, inInclusiveRange(18, 22));
    });

    test('60 Hz input is also held to 20 fps', () {
      final r = Rig();
      r.live();
      for (var i = 0; i < 600; i++) {
        r.tick(17);
      }
      final fps = r.sent.length / (600 * 17 / 1000);
      expect(fps, inInclusiveRange(18, 21));
    });

    test('never closer than minGap (25 ms)', () {
      final r = Rig();
      r.live();
      final times = <int>[];
      r.sent.clear();
      for (var i = 0; i < 400; i++) {
        final before = r.sent.length;
        r.tick(7); // very fast input, all of it loud onsets
        if (r.sent.length > before) times.add(r.nowUs);
      }
      for (var i = 1; i < times.length; i++) {
        expect(times[i] - times[i - 1], greaterThanOrEqualTo(25000));
      }
    });

    test('never more than 30 in any sliding second, whatever arrives', () {
      // Settings that would send ~100/s if nothing else stopped them.
      final r = Rig(
        interval: const Duration(milliseconds: 10),
        minGap: const Duration(milliseconds: 1),
      );
      r.live();
      final times = <int>[];
      for (var i = 0; i < 1500; i++) {
        final before = r.sent.length;
        // Loud kicks at every other tick on a 26 ms tick: as dense as it gets.
        final hops = (i % 2 == 0)
            ? Float32List.fromList(List.filled(8, 0.08))
            : Float32List.fromList(List.filled(8, 0.0005));
        r.tick(12, frame(hops: hops));
        if (r.sent.length > before) times.add(r.nowUs);
      }
      expect(times.length, greaterThan(100), reason: 'it did send');
      for (var i = 0; i + 30 < times.length; i++) {
        expect(times[i + 30] - times[i], greaterThanOrEqualTo(1000000));
      }
    });

    test('onsets do not push a second past 30 frames', () {
      final r = Rig();
      r.live();
      var seconds = 0.0;
      for (var i = 0; i < 600; i++) {
        // A kick every 110 ms, the detector's refractory period.
        final hops = (i % 3 == 0)
            ? Float32List.fromList(List.filled(8, 0.08))
            : Float32List.fromList(List.filled(8, 0.0005));
        r.tick(37, frame(hops: hops));
        seconds += 0.037;
      }
      expect(r.sent.length / seconds, lessThanOrEqualTo(30));
    });
  });
}
