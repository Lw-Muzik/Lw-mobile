import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
// Lowercase on purpose: the same URI visualizer_widget.dart reaches it by, so
// the beat stream (a static) is the one the iOS handler publishes to.
import '../helpers/audio_visualizer.dart';
import '../services/artwork_service.dart';
import 'bass_beat.dart';
import 'beat_detector.dart';
import 'beat_frame.dart';
import 'radial_motion.dart';
import 'spectrum-visualiser.dart';
import 'poweramp_visualizers.dart';
import '3d_visualizers.dart';
import '3d_visualizers_tier2.dart';
import '3d_visualizers_tier3.dart';

class WaveVisualizer extends StatefulWidget {
  final List<int> audioData; // waveform: unsigned bytes 0-255, center 128
  final List<int> fftData; // FFT: byte pairs [mag, phase], from native
  final double width;
  final String selector;
  final double height;
  final Color color;
  final double reactivity;

  const WaveVisualizer({
    super.key,
    required this.audioData,
    required this.width,
    required this.height,
    this.fftData = const [],
    this.color = Colors.white,
    this.selector = "circular",
    this.reactivity = 0.15,
  });

  @override
  State<WaveVisualizer> createState() => _WaveVisualizerState();
}

class _WaveVisualizerState extends State<WaveVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Frequency spectrum (from FFT) — 0.0 to 1.0 per band
  // Used by: spectrum, radial, mirror, dots, terrain
  final List<double> _freqBands = List.filled(256, 0.0);

  // Waveform amplitude (from time-domain) — signed -1..1 centered at 0
  // Used by: waveform line
  final List<double> _waveform = List.filled(512, 0.0);

  // FFT history ring buffer for terrain/waterfall visualizers
  static const int _maxHistory = 30;
  final List<List<double>> _fftHistory = [];

  double get _attackRate => widget.reactivity;
  double get _decayRate => widget.reactivity * 0.7;

  // Auto-idle: the 60fps render loop runs only while fresh audio frames are
  // arriving. When playback pauses/stops the frames stop, this timer fires,
  // and we halt the controller so the painters no longer repaint. (Previously
  // the loop ran forever — repainting a paused/silent track every frame, a
  // major CPU/GPU/heat drain.) Route-visibility is handled separately by
  // Flutter's TickerMode, which mutes this vsync ticker when off-screen.
  Timer? _idleTimer;
  bool _running = false;
  static const Duration _idleTimeout = Duration(milliseconds: 400);

  // ── Radial spectrum ──
  //
  // A CustomPainter is rebuilt every frame and cannot hold any of this, so it
  // lives here and is advanced exactly once per tick in [_advanceRadial].
  //
  // The bounce comes from the native tap's bass report ([BeatFrame]): energy
  // below ~150 Hz in ~6 ms hops of the audio being heard, which [BassBeat]
  // turns into hits and [RadialMotion] into the swell, flare and rings. The
  // crown's bars come from the same frames' absolute band levels.
  final BassBeat _bass = BassBeat();
  final RadialMotion _motion = RadialMotion();
  final List<double> _crown = List.filled(kCrownBars, 0.0);
  final List<double> _crownTarget = List.filled(kCrownBars, 0.0);
  final List<double> _tilted = List.filled(_crownBands, 0.0);
  double _bandRef = -60;
  StreamSubscription<BeatFrame>? _beatSub;
  bool? _beatSynced;
  final Stopwatch _clock = Stopwatch()..start();
  int _motionUs = 0;
  int _crownUs = 0;
  int _beatUs = -1 << 40;

  // Without beat frames (an older native build, or none arriving), the old
  // whole-mix detector still gives a pulse — better than a still picture.
  final BeatState _beatDetector = BeatState();
  double _prevPulse = 0;

  /// Cover art for the core, and the song it belongs to.
  ui.Image? _cover;
  int? _coverSongId;
  bool _coverLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _markActive();
  }

  /// New audio activity — ensure the loop is running and reset the idle timer.
  void _markActive() {
    if (!_running) {
      _running = true;
      _controller.repeat();
    }
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, _goIdle);
  }

  /// Advances everything the radial spectrum carries between frames.
  ///
  /// Called once per animation tick, never from `paint`: Flutter may repaint
  /// for reasons that have nothing to do with time passing, and a ring that
  /// expanded on every repaint would travel at a speed set by how busy the
  /// rest of the screen was.
  void _advanceRadial() {
    final nowUs = _clock.elapsedMicroseconds;
    _advanceMotionTo(nowUs);
    final dt = _crownUs == 0 ? 1 / 60 : math.min(0.1, (nowUs - _crownUs) / 1e6);
    _crownUs = nowUs;

    if (nowUs - _beatUs > _beatStaleUs) _fallbackBeat(dt);

    // Bars rise in ~25 ms and fall over ~110 ms: a kick lands as a jump, and
    // the crown still reads as a spectrum rather than flicker.
    final rise = 1 - math.exp(-dt / 0.025);
    final fall = 1 - math.exp(-dt / 0.11);
    for (var i = 0; i < kCrownBars; i++) {
      final t = _crownTarget[i];
      _crown[i] += (t - _crown[i]) * (t > _crown[i] ? rise : fall);
    }
  }

  /// Subscribes to the native bass report the first time the radial scene is
  /// drawn — not before, so other visualizers do not pay for it.
  void _ensureBeatFeed() {
    if (_beatSub != null) return;
    _beatSub = AudioVisualizer.beatFrames.listen(
      _onBeatFrame,
      onError: (Object _) {},
    );
  }

  void _onBeatFrame(BeatFrame frame) {
    final nowUs = _clock.elapsedMicroseconds;
    _advanceMotionTo(nowUs);
    final sinceLast = (nowUs - _beatUs) / 1e6;
    _beatUs = nowUs;
    // Unsynced hops read the newest audio, synced ones what is heard: the
    // switch jumps the stream ~0.3 s, which must not read as a hit.
    if (_beatSynced != null && _beatSynced != frame.synced) _bass.reset();
    _beatSynced = frame.synced;
    for (final hit in _bass.add(frame.hops, frame.hopSeconds)) {
      _motion.hit(hit);
    }
    _motion.level(_bass.level);
    if (frame.bandsDb.length > _crownBands) {
      _aimCrown(frame.bandsDb, frame.sampleRate, sinceLast.clamp(0.0, 0.2));
    }
  }

  void _advanceMotionTo(int nowUs) {
    if (_motionUs != 0) {
      _motion.advance(math.min(0.1, (nowUs - _motionUs) / 1e6));
    }
    _motionUs = nowUs;
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
  void _fallbackBeat(double dt) {
    double peak = 0;
    double sumSq = 0;
    for (final v in _waveform) {
      final a = v.abs();
      if (a > peak) peak = a;
      sumSq += v * v;
    }
    final rms = _waveform.isEmpty ? 0.0 : math.sqrt(sumSq / _waveform.length);
    _beatDetector.step(math.min(1.0, math.max(rms * 1.25, peak)), dt);
    final pulse = _beatDetector.pulse;
    if (pulse > _prevPulse + 0.04) {
      _motion.hit(
        BassHit(age: 0, strength: pulse, gain: pulse - _prevPulse, onset: true),
      );
    }
    _prevPulse = pulse;
    for (var i = 0; i < kCrownBars; i++) {
      final idx = (math.pow(i / kCrownBars, 1.3) * (_freqBands.length - 1))
          .round();
      _crownTarget[i] = _freqBands[idx].clamp(0.0, 1.0);
    }
  }

  /// Loads the playing track's artwork for the core, once per track.
  ///
  /// Desktop reads a cover URL straight off its store; here the art has to be
  /// extracted to a file and decoded, so it is done off the paint path and the
  /// gradient core stands in until it arrives — which is also what desktop
  /// shows when a track has no art at all.
  Future<void> _ensureCover() async {
    final controller = AppController.instance;
    if (controller.songs.isEmpty) return;
    final song = controller
        .songs[controller.songId.clamp(0, controller.songs.length - 1)];
    if (song.id == _coverSongId || _coverLoading) return;
    _coverLoading = true;
    try {
      final path = await ArtworkService.instance.pathFor(
        id: song.id,
        data: song.data,
      );
      if (!mounted) return;
      if (path == null) {
        _cover?.dispose();
        _cover = null;
        _coverSongId = song.id;
        return;
      }
      final bytes = await File(path).readAsBytes();
      final decoded = await ui.instantiateImageCodec(bytes, targetWidth: 512);
      final frame = await decoded.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      _cover?.dispose();
      _cover = frame.image;
      _coverSongId = song.id;
    } catch (_) {
      // No art is a normal outcome, not a failure worth surfacing: the core
      // simply keeps the brand gradient.
      _coverSongId = song.id;
    } finally {
      _coverLoading = false;
    }
  }

  /// No fresh frames for [_idleTimeout] — freeze the loop until data resumes.
  void _goIdle() {
    if (_running && mounted) {
      _running = false;
      _controller.stop();
    }
  }

  @override
  void didUpdateWidget(covariant WaveVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent hands us fresh list instances when new FFT/waveform data
    // arrives; identical references mean nothing new to draw.
    if (!identical(oldWidget.audioData, widget.audioData) ||
        !identical(oldWidget.fftData, widget.fftData)) {
      _markActive();
    }
  }

  /// Detect iOS FFT format: all odd-index bytes are 0 (imaginary = 0).
  /// Android format has varying imaginary components.
  bool _isIosFormatFft(List<int> fft) {
    if (fft.length < 8) return false;
    int zeroCount = 0;
    final checkCount = math.min(10, fft.length ~/ 2);
    for (int i = 0; i < checkCount; i++) {
      if (fft[i * 2 + 1] == 0) zeroCount++;
    }
    return zeroCount >= checkCount - 1;
  }

  @override
  void dispose() {
    _beatSub?.cancel();
    _idleTimer?.cancel();
    _controller.dispose();
    // A decoded ui.Image is native memory the GC does not account for; leaking
    // one per track is how a visualizer quietly becomes a memory problem.
    _cover?.dispose();
    _cover = null;
    super.dispose();
  }

  /// Process FFT data into frequency bands.
  ///
  /// Android FFT format (from Visualizer API):
  ///   [DC, Nyquist, Re[1], Im[1], Re[2], Im[2], ...]
  ///   Values are signed bytes (-128..127) transmitted as unsigned (0..255).
  ///   Magnitude = sqrt(Re² + Im²), then normalize.
  ///
  /// iOS FFT format (from HypeAudioTap):
  ///   [mag[0], 0, mag[1], 0, mag[2], 0, ...]
  ///   Magnitudes already computed natively, 0-255 with adaptive normalization.
  void _updateFreqBands() {
    if (widget.fftData.length >= 4) {
      final fftLen = widget.fftData.length;
      final numBins = (fftLen - 2) ~/ 2; // skip DC and Nyquist
      if (numBins <= 0) return;

      // Step 1: Compute magnitude for each FFT bin
      // Detect format: iOS sends [mag, 0, mag, 0, ...] — imaginary is always 0
      // Android sends [DC, Nyq, Re, Im, Re, Im, ...] — imaginary varies
      final isIosFormat = _isIosFormatFft(widget.fftData);

      final magnitudes = List<double>.filled(numBins, 0.0);
      double peakMag = 0.0001;

      if (isIosFormat) {
        // iOS: even indices are pre-computed magnitudes (0-255)
        for (int i = 0; i < numBins; i++) {
          magnitudes[i] = widget.fftData[i * 2].clamp(0, 255) / 255.0;
          if (magnitudes[i] > peakMag) peakMag = magnitudes[i];
        }
      } else {
        // Android: compute magnitude from signed Re/Im pairs
        // Skip byte[0] (DC) and byte[1] (Nyquist)
        for (int i = 0; i < numBins; i++) {
          final rawRe = widget.fftData[2 + i * 2];
          final rawIm = widget.fftData[2 + i * 2 + 1];
          // Convert unsigned byte to signed: 0..127 stays, 128..255 → -128..-1
          final re = (rawRe > 127 ? rawRe - 256 : rawRe).toDouble();
          final im = (rawIm > 127 ? rawIm - 256 : rawIm).toDouble();
          magnitudes[i] = math.sqrt(re * re + im * im);
          if (magnitudes[i] > peakMag) peakMag = magnitudes[i];
        }
      }

      // Step 2: Map bins to frequency bands with logarithmic scaling
      for (int i = 0; i < _freqBands.length; i++) {
        final t = i / _freqBands.length;
        // Log frequency mapping: more resolution for bass
        final binIdx = (math.pow(t, 1.6) * numBins).floor().clamp(
          0,
          numBins - 1,
        );

        // Average a small neighborhood for smoother bands
        double sum = 0;
        int count = 0;
        final spread = math.max(1, numBins ~/ _freqBands.length);
        for (int j = -spread; j <= spread; j++) {
          final idx = (binIdx + j).clamp(0, numBins - 1);
          sum += magnitudes[idx];
          count++;
        }
        final avgMag = sum / count;

        // Normalize relative to peak for consistent 0..1 range
        double normalized;
        if (isIosFormat) {
          normalized = avgMag; // iOS data is already 0..1
        } else {
          // Android: normalize with dB-like curve for perceptual loudness
          final linear = avgMag / peakMag;
          // Compress dynamic range: emphasize quiet frequencies
          normalized = math.pow(linear, 0.6).clamp(0.0, 1.0).toDouble();
        }

        // Bass boost for lowest bands
        final bassBoost = (1.0 - t) * 0.3;
        final boosted = (normalized * (1.0 + bassBoost)).clamp(0.0, 1.0);

        final factor = boosted > _freqBands[i] ? _attackRate : _decayRate;
        _freqBands[i] += (boosted - _freqBands[i]) * factor;
      }
    } else if (widget.audioData.isNotEmpty) {
      // Fallback: approximate frequency bands from waveform using zero-crossing
      // rate analysis at different window sizes (cheap, no trig).
      // Small windows → high freq content, large windows → low freq content.
      final inputLen = widget.audioData.length;

      for (int i = 0; i < _freqBands.length; i++) {
        final t = i / _freqBands.length;
        // Log-scaled window: bass bands use large windows, treble uses small
        final windowSize = math.max(
          2,
          (inputLen * math.pow(1.0 - t, 2.0)).round(),
        );
        final start = ((t * 0.8) * inputLen).round().clamp(
          0,
          inputLen - windowSize,
        );

        // Compute RMS energy in this window
        double sum = 0;
        for (int j = start; j < start + windowSize && j < inputLen; j++) {
          final v = (widget.audioData[j] - 128) / 128.0;
          sum += v * v;
        }
        final rms = math.sqrt(sum / windowSize);
        final target = (rms * 3.0).clamp(0.0, 1.0);

        final factor = target > _freqBands[i] ? _attackRate : _decayRate;
        _freqBands[i] += (target - _freqBands[i]) * factor;
      }
    } else {
      // Decay to silence
      for (int i = 0; i < _freqBands.length; i++) {
        _freqBands[i] += (0.0 - _freqBands[i]) * _decayRate;
      }
    }
  }

  /// Process waveform data for time-domain visualizers (oscilloscope line).
  void _updateWaveform() {
    if (widget.audioData.isEmpty) {
      for (int i = 0; i < _waveform.length; i++) {
        _waveform[i] += (0.0 - _waveform[i]) * _decayRate;
      }
      return;
    }

    final inputLen = widget.audioData.length;
    for (int i = 0; i < _waveform.length; i++) {
      final rawIdx = (i * inputLen / _waveform.length).floor().clamp(
        0,
        inputLen - 1,
      );
      // Signed: -1.0 to 1.0
      final target = (widget.audioData[rawIdx] - 128) / 128.0;
      final factor = target.abs() > _waveform[i].abs()
          ? _attackRate
          : _decayRate;
      _waveform[i] += (target - _waveform[i]) * factor;
    }
  }

  @override
  Widget build(BuildContext context) {
    _updateFreqBands();
    _updateWaveform();

    // Push current frame into FFT history for terrain/waterfall
    if (widget.selector == 'terrain_3d' || widget.selector == 'waterfall') {
      _fftHistory.insert(0, List<double>.from(_freqBands));
      if (_fftHistory.length > _maxHistory) _fftHistory.removeLast();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return _buildVisualizer(widget.selector);
      },
    );
  }

  RadialBurstVisualizer _radialPainter() {
    _ensureBeatFeed();
    return RadialBurstVisualizer(
      crown: _crown,
      swell: _motion.swell,
      flare: _motion.flare,
      rings: _motion.rings,
      cover: _cover,
    );
  }

  Widget _buildVisualizer(String selector) {
    // Advanced here rather than in the painter: this runs once per animation
    // tick, which is the clock the desktop scene's rAF loop uses.
    //
    // Unconditional, not gated on `selector == 'radial'`, because the default
    // branch of the switch below also renders the radial scene. Gating would
    // mean keeping a list of "every selector that is not radial" in step with
    // that switch forever, and the first time the two drifted the fallback
    // would render a frozen ring. The work is 96 lerps and one pass over the
    // waveform.
    _advanceRadial();
    unawaited(_ensureCover());
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(widget.width, widget.height),
        painter: switch (selector) {
          'bars' => SpectrumVisualizer(
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
          ),
          'radial' => _radialPainter(),
          'mirror_bars' => MirrorBarsVisualizer(
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
          ),
          'line' => WaveformLineVisualizer(
            audioData: _waveform,
            color: widget.color,
            time: _controller.value,
          ),
          'terrain' => TerrainVisualizer(
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
          ),
          'dots' => DotMatrixVisualizer(
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
          ),
          'silk' => SilkWavesVisualizer(
            audioData: _waveform,
            color: widget.color,
            time: _controller.value,
          ),
          'lissajous' => LissajousVisualizer(
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
          ),
          'windmill' => WindmillVisualizer(
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
          ),
          // ── 3D Visualizers (Tier 1) ──
          'neon_grid' => NeonGridHorizonVisualizer(
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
          ),
          'spectrum_ring' => SpectrumRing3DVisualizer(
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
          ),
          'ribbon_trail' => RibbonTrailVisualizer(
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
          ),
          'lissajous_3d' => Lissajous3DVisualizer(
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
          ),
          'particle_field' => ParticleFieldVisualizer(
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
          ),
          'waveform_tunnel' => WaveformTunnelVisualizer(
            audioData: _waveform,
            color: widget.color,
            time: _controller.value,
          ),
          'kaleidoscope' => KaleidoscopeTunnelVisualizer(
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
          ),
          // ── 3D Visualizers (Tier 2) ──
          'terrain_3d' => AudioTerrainVisualizer(
            audioData: _freqBands,
            fftHistory: _fftHistory,
            color: widget.color,
            time: _controller.value,
          ),
          'mesh_sphere' => MeshSphereVisualizer(
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
          ),
          'morphing_orb' => MorphingOrbVisualizer(
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
          ),
          'reactive_geo' => ReactiveGeometryVisualizer(
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
          ),
          'waterfall' => WaterfallSpectrogramVisualizer(
            audioData: _freqBands,
            fftHistory: _fftHistory,
            color: widget.color,
            time: _controller.value,
          ),
          // ── 3D Visualizers (Tier 3) ──
          'metaball' => MetaballBlobVisualizer(
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
          ),
          'milkdrop_warp' => MilkdropWarpVisualizer(
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
          ),
          'fractal_flame' => FractalFlameVisualizer(
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
          ),
          _ => _radialPainter(),
        },
      ),
    );
  }
}

/// Bands 1..51 of the native 64: ~43 Hz to ~14 kHz at 44.1 kHz. Above that,
/// lossy audio is mostly empty and the bars there would never move.
const int _crownBands = 51;

/// After this long without a beat frame, the scene falls back to the old pulse.
const int _beatStaleUs = 400000;

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
