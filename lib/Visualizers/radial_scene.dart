/// The radial visualizer's state between frames: hits found in the native
/// bass report, put on screen when they are heard.
///
/// # Timing
///
/// Android's tap reads the audio ~200 ms ahead of what is being heard and
/// says when the last hop of each frame will be heard ([BeatFrame.heardAtUs]).
/// That lead is spent here:
///
/// - **Every hit waits for its moment.** Hits and bar levels are queued with
///   the time they will be heard, and applied by the frame that will be on
///   screen at that time — not the frame being built now.
/// - **"On screen" is measured, not assumed.** A frame reaches the display
///   [displayLatencyUs] after it is built: its build-to-raster span (from
///   Flutter's frame timings) plus ~3.5 refreshes for the display path. On
///   the Lenovo tablet that is ~100 ms (a 45 ms span at 60 Hz); drawing a hit
///   when it was heard put the bounce ~110 ms after the kick in screen
///   recordings.
///
/// Without a heard time (iOS; Android before playback starts) hits apply as
/// they arrive.
///
/// All times are microseconds on one monotonic clock — `Timeline.now` in the
/// app, which on Android is the CLOCK_MONOTONIC the native side stamps with.
library;

import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show FrameTiming;

import 'bass_beat.dart';
import 'beat_detector.dart';
import 'beat_frame.dart';
import 'radial_motion.dart';

/// Bands 1..51 of the native 64: ~43 Hz to ~14 kHz at 44.1 kHz. Above that,
/// lossy audio is mostly empty and the bars there would never move.
const int _crownBands = 51;

/// After this long without a beat frame, the scene falls back to the old
/// whole-mix pulse.
const int _staleUs = 400000;

/// Queued items more than this far behind the screen are dropped, not drawn.
const int _tooLateUs = 500000;

class RadialScene {
  RadialScene({this.defaultDisplayLatencyUs = 100000});

  final BassBeat _bass = BassBeat();
  final RadialMotion _motion = RadialMotion();
  final BeatState _fallback = BeatState();

  /// Bar levels as drawn, bass first.
  final List<double> crown = List.filled(kCrownBars, 0.0);
  final List<double> _crownTarget = List.filled(kCrownBars, 0.0);
  final List<double> _tilted = List.filled(_crownBands, 0.0);
  double _bandRef = -60;

  final Queue<(int, BassHit)> _hits = Queue();
  final Queue<_Bands> _bands = Queue();

  bool? _synced;
  int _lastFrameUs = -1 << 50;
  int _motionUs = 0;
  int _crownUs = 0;
  int _bandsUs = 0;
  double _prevPulse = 0;

  /// What [displayLatencyUs] starts from, before any frame has been timed.
  final int defaultDisplayLatencyUs;
  double _spanUs = -1;
  double _refreshUs = 16667;

  double get swell => _motion.swell;
  double get flare => _motion.flare;
  List<RadialRing> get rings => _motion.rings;

  /// Whether beat frames are arriving.
  bool liveAt(int nowUs) => nowUs - _lastFrameUs <= _staleUs;

  /// How long after it is built a frame is on screen: its build-to-raster
  /// span, then ~3.5 refreshes — waiting for the compositor to latch it, the
  /// refresh it is presented on, scan-out, and the rest of the display path.
  /// 2.5 (the latch-present-scan-out model alone) still left bounces ~30-50 ms
  /// after their kicks in screen recordings of three songs.
  int get displayLatencyUs => _spanUs < 0
      ? defaultDisplayLatencyUs
      : (_spanUs + 3.5 * _refreshUs).round().clamp(16000, 200000);

  /// Learns how long frames take to reach the screen.
  void observeFrameTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final span = t.totalSpan.inMicroseconds.toDouble();
      if (span <= 0 || span > 500000) continue;
      // Quick to learn, slow to forget: one long frame should not throw the
      // timing off, a device that is always slow should be learned fast.
      _spanUs = _spanUs < 0 ? span : _spanUs + (span - _spanUs) * 0.05;
    }
  }

  /// Sets the display's refresh period, for [displayLatencyUs].
  set refreshPeriodUs(double us) {
    if (us > 4000 && us < 50000) _refreshUs = us;
  }

  /// Takes one frame of the native bass report, received at [nowUs].
  void addFrame(BeatFrame frame, int nowUs) {
    final sinceLast = (nowUs - _lastFrameUs) / 1e6;
    _lastFrameUs = nowUs;
    // Unsynced hops read the newest audio, synced ones what is heard: the
    // switch jumps the stream ~0.3 s, which must not read as a hit.
    if (_synced != null && _synced != frame.synced) {
      _bass.reset();
      _hits.clear();
      _bands.clear();
    }
    _synced = frame.synced;

    // Without a heard time, treat the newest hop as due on the frame being
    // built now.
    final endUs = frame.heardAtUs ?? nowUs + displayLatencyUs;
    for (final hit in _bass.add(frame.hops, frame.hopSeconds)) {
      _hits.add((endUs - (hit.age * 1e6).round(), hit));
    }
    if (frame.bandsDb.length > _crownBands) {
      _bands.add(
        _Bands(
          endUs,
          Float32List.fromList(frame.bandsDb),
          frame.sampleRate,
          _bass.level,
          sinceLast.clamp(0.0, 0.2),
        ),
      );
    }
    if (frame.heardAtUs == null) _applyDue(nowUs + displayLatencyUs);
  }

  /// Moves the scene to what should be on screen when a frame built at
  /// [nowUs] is displayed. [waveform] and [spectrum] drive the fallback when
  /// no beat frames arrive.
  void tick(
    int nowUs, {
    List<double> waveform = const [],
    List<double> spectrum = const [],
  }) {
    final showUs = nowUs + displayLatencyUs;
    final dt = _crownUs == 0 ? 1 / 60 : math.min(0.1, (nowUs - _crownUs) / 1e6);
    _crownUs = nowUs;

    _applyDue(showUs);
    if (!liveAt(nowUs)) _fallbackStep(dt, waveform, spectrum);

    // Bars rise in ~25 ms and fall over ~110 ms: a kick lands as a jump, and
    // the crown still reads as a spectrum rather than flicker.
    final rise = 1 - math.exp(-dt / 0.025);
    final fall = 1 - math.exp(-dt / 0.11);
    for (var i = 0; i < kCrownBars; i++) {
      final t = _crownTarget[i];
      crown[i] += (t - crown[i]) * (t > crown[i] ? rise : fall);
    }
  }

  /// Applies every queued hit and bar level due by [showUs], and moves the
  /// motion there.
  void _applyDue(int showUs) {
    if (_motionUs != 0 && showUs > _motionUs) {
      _motion.advance(math.min(0.1, (showUs - _motionUs) / 1e6));
    }
    // Never backwards: the latency estimate can shrink between frames.
    if (showUs > _motionUs) _motionUs = showUs;
    final at = _motionUs;

    while (_hits.isNotEmpty && _hits.first.$1 <= at) {
      final (heardUs, hit) = _hits.removeFirst();
      final lateUs = at - heardUs;
      if (lateUs > _tooLateUs) continue;
      _motion.hit(
        BassHit(
          age: lateUs / 1e6,
          strength: hit.strength,
          gain: hit.gain,
          onset: hit.onset,
        ),
      );
    }
    _Bands? due;
    while (_bands.isNotEmpty && _bands.first.heardUs <= at) {
      due = _bands.removeFirst();
    }
    if (due != null && at - due.heardUs <= _tooLateUs) {
      final dt = _bandsUs == 0 ? due.dt : (due.heardUs - _bandsUs) / 1e6;
      _bandsUs = due.heardUs;
      _aimCrown(due.db, due.sampleRate, dt.clamp(0.0, 0.2));
      _motion.level(due.bassLevel);
    }
  }

  /// Sets the bars' targets from absolute band levels.
  ///
  /// +3 dB per octave about 1 kHz so treble, whose energy is spread thin
  /// across wide bands, is not drawn flat; then 42 dB below the loudest band
  /// lately maps to 0..1, curved so quiet bands stay low and peaks stand out.
  /// Measured on three songs, bass bars sit near 0.85-0.95 on a kick and fall
  /// between them; the treble moves around 0.2-0.5.
  void _aimCrown(Float32List db, double sampleRate, double dt) {
    var loudest = -200.0;
    for (var b = 0; b < _crownBands; b++) {
      final band = b + 1; // band 0 is ~20 Hz: rumble, not music
      final v =
          db[band] +
          3 * math.log(_bandCentre(band, sampleRate) / 1000) / math.ln2;
      _tilted[b] = v;
      if (v > loudest) loudest = v;
    }
    _bandRef = loudest > _bandRef
        ? loudest
        : math.max(loudest, _bandRef - 8 * dt);
    const range = 42.0;
    for (var i = 0; i < kCrownBars; i++) {
      final pos = i * (_crownBands - 1) / (kCrownBars - 1);
      final k = pos.floor();
      final f = pos - k;
      final x = k + 1 < _crownBands
          ? _tilted[k] * (1 - f) + _tilted[k + 1] * f
          : _tilted[k];
      final v = ((x - (_bandRef - range)) / range).clamp(0.0, 1.0);
      _crownTarget[i] = math.pow(v, 1.6).toDouble();
    }
  }

  /// What moves the scene when no beat frames arrive: the old whole-mix pulse,
  /// and the shared spectrum for the bars.
  void _fallbackStep(double dt, List<double> waveform, List<double> spectrum) {
    double peak = 0;
    double sumSq = 0;
    for (final v in waveform) {
      final a = v.abs();
      if (a > peak) peak = a;
      sumSq += v * v;
    }
    final rms = waveform.isEmpty ? 0.0 : math.sqrt(sumSq / waveform.length);
    _fallback.step(math.min(1.0, math.max(rms * 1.25, peak)), dt);
    final pulse = _fallback.pulse;
    if (pulse > _prevPulse + 0.04) {
      _motion.hit(
        BassHit(age: 0, strength: pulse, gain: pulse - _prevPulse, onset: true),
      );
    }
    _prevPulse = pulse;
    if (spectrum.isEmpty) return;
    for (var i = 0; i < kCrownBars; i++) {
      final idx = (math.pow(i / kCrownBars, 1.3) * (spectrum.length - 1))
          .round();
      _crownTarget[i] = spectrum[idx].clamp(0.0, 1.0);
    }
  }
}

class _Bands {
  _Bands(this.heardUs, this.db, this.sampleRate, this.bassLevel, this.dt);

  final int heardUs;
  final Float32List db;
  final double sampleRate;
  final double bassLevel;
  final double dt;
}

/// Centre frequency of native band [band] (fft_visualizer.h's power-curve
/// edges over a 2048-point FFT).
double _bandCentre(int band, double sampleRate) {
  final lo = _bandEdges[band];
  final hi = _bandEdges[band + 1];
  return (lo + hi - 1) / 2 * sampleRate / 2048;
}

final List<int> _bandEdges = () {
  final edges = [
    for (var b = 0; b <= 64; b++) 1 + ((b / 64) * (b / 64) * 1023).floor(),
  ];
  for (var b = 1; b <= 64; b++) {
    if (edges[b] <= edges[b - 1]) edges[b] = edges[b - 1] + 1;
  }
  return edges;
}();
