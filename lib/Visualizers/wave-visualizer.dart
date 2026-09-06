import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../services/artwork_service.dart';
import 'beat_detector.dart';
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

  // ── Radial spectrum: the state the desktop scene keeps in its rAF closure ──
  //
  // A CustomPainter is rebuilt every frame and cannot hold any of this, so it
  // lives here and is advanced exactly once per tick in [_advanceRadial].
  final List<double> _radialBars = List.filled(kRadialBars, 0.0);
  final List<RadialRing> _radialRings = [];
  // Desktop runs one detector per channel and takes the louder pulse. The
  // visualizer tap here delivers a single mono waveform, so there is only one
  // to run — feeding the same level to two would just be the same number twice.
  final BeatState _beatDetector = BeatState();
  double _prevBeat = 0;
  double _beat = 0;
  int _lastTickUs = 0;

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
    final nowUs = DateTime.now().microsecondsSinceEpoch;
    // First tick has no previous frame to measure against; 1/60 is the honest
    // guess and only affects one frame.
    final dt = _lastTickUs == 0
        ? 1 / 60
        : math.min(0.05, (nowUs - _lastTickUs) / 1e6);
    _lastTickUs = nowUs;

    // Level, the way desktop derives it: the louder of peak and 1.25x RMS.
    double peak = 0;
    double sumSq = 0;
    for (final v in _waveform) {
      final a = v.abs();
      if (a > peak) peak = a;
      sumSq += v * v;
    }
    final rms = _waveform.isEmpty ? 0.0 : math.sqrt(sumSq / _waveform.length);
    final level = math.min(1.0, math.max(rms * 1.25, peak));

    _beatDetector.step(level, dt);
    _beat = _beatDetector.pulse;

    // Bars: resample the spectrum to 96 and ease 35% of the way each frame.
    for (int i = 0; i < kRadialBars; i++) {
      final target = _freqBands.isEmpty
          ? 0.0
          : _freqBands[((i / kRadialBars) * _freqBands.length).floor().clamp(
                  0,
                  _freqBands.length - 1,
                )]
                .clamp(0.0, 1.0);
      _radialBars[i] += (target - _radialBars[i]) * 0.35;
    }

    // A shockwave on the rising edge of the beat, not while it stays high.
    if (_beat > 0.5 && _prevBeat <= 0.5) {
      final minDim = math.min(widget.width, widget.height);
      _radialRings.add(RadialRing(minDim * 0.2, 0.5));
    }
    _prevBeat = _beat;

    final minDim = math.min(widget.width, widget.height);
    for (int k = _radialRings.length - 1; k >= 0; k--) {
      final ring = _radialRings[k];
      ring.r += dt * minDim * 0.9;
      ring.a -= dt * 0.9;
      if (ring.a <= 0) _radialRings.removeAt(k);
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
          'radial' => RadialBurstVisualizer(
            bars: _radialBars,
            beat: _beat,
            rings: _radialRings,
            cover: _cover,
          ),
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
          _ => RadialBurstVisualizer(
            bars: _radialBars,
            beat: _beat,
            rings: _radialRings,
            cover: _cover,
          ),
        },
      ),
    );
  }
}
