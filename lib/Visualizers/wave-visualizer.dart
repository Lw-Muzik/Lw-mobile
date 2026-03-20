import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'CircularBarVisualizer.dart';
import 'spectrum-visualiser.dart';
import 'poweramp_visualizers.dart';

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

  double get _attackRate => widget.reactivity;
  double get _decayRate => widget.reactivity * 0.45;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Process FFT data into frequency bands.
  /// FFT format: pairs of [magnitude, phase] bytes (0-255).
  /// Lower indices = lower frequencies (bass), higher = treble.
  void _updateFreqBands() {
    if (widget.fftData.length >= 4) {
      // Use real FFT data — extract magnitude from byte pairs
      final halfLen = widget.fftData.length ~/ 2;
      final bandCount = math.min(halfLen, _freqBands.length);

      for (int i = 0; i < _freqBands.length; i++) {
        final fftIdx = (i * bandCount ~/ _freqBands.length).clamp(0, halfLen - 1);
        // Magnitude is in even indices (real part of pair)
        final mag = widget.fftData[fftIdx * 2].clamp(0, 255) / 255.0;

        final target = mag;
        final factor = target > _freqBands[i] ? _attackRate : _decayRate;
        _freqBands[i] += (target - _freqBands[i]) * factor;
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
