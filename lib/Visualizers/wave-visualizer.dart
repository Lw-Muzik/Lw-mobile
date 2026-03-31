import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'CircularBarVisualizer.dart';
import 'spectrum-visualiser.dart';
import 'poweramp_visualizers.dart';
import '3d_visualizers.dart';
import '3d_visualizers_tier2.dart';
import '3d_visualizers_tier3.dart';

class WaveVisualizer extends StatefulWidget {
  final List<int> audioData;   // waveform: unsigned bytes 0-255, center 128
  final List<int> fftData;     // FFT: byte pairs [mag, phase], from native
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
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
    _controller.dispose();
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
        final binIdx = (math.pow(t, 1.6) * numBins).floor().clamp(0, numBins - 1);

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
        final windowSize = math.max(2, (inputLen * math.pow(1.0 - t, 2.0)).round());
        final start = ((t * 0.8) * inputLen).round().clamp(0, inputLen - windowSize);

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
      final rawIdx = (i * inputLen / _waveform.length).floor()
          .clamp(0, inputLen - 1);
      // Signed: -1.0 to 1.0
      final target = (widget.audioData[rawIdx] - 128) / 128.0;
      final factor = target.abs() > _waveform[i].abs() ? _attackRate : _decayRate;
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
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
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
            audioData: _freqBands,
            color: widget.color,
            time: _controller.value,
          ),
        },
      ),
    );
  }
}
