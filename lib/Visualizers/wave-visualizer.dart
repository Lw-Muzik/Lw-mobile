import 'package:flutter/material.dart';

import 'CircularBarVisualizer.dart';
import 'spectrum-visualiser.dart';
import 'poweramp_visualizers.dart';

class WaveVisualizer extends StatefulWidget {
  final List<int> audioData;
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
  final List<double> _smoothedData = List.filled(512, 0.0);   // amplitude 0..1
  final List<double> _signedData = List.filled(512, 0.5);     // signed 0..1 (0.5=center)

  /// Decay factor — always half the attack so bars don't snap back
  /// to zero between beats.
  double get _smoothingUp => widget.reactivity;
  double get _smoothingDown => widget.reactivity * 0.53;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  void _updateAudioData() {
    if (widget.audioData.isEmpty) {
      for (int i = 0; i < _smoothedData.length; i++) {
        _smoothedData[i] += (0.0 - _smoothedData[i]) * _smoothingDown;
        _signedData[i] += (0.5 - _signedData[i]) * _smoothingDown;
      }
      return;
    }

    final inputLength = widget.audioData.length;
    for (int i = 0; i < _smoothedData.length; i++) {
      final rawIndex = (i * inputLength / _smoothedData.length).floor().clamp(
        0,
        inputLength - 1,
      );
      final raw = widget.audioData[rawIndex];

      // Amplitude (0.0 = silence, 1.0 = max) — for bars, radial, dots, terrain
      final ampTarget = (raw - 128).abs() / 128.0;
      final ampFactor = ampTarget > _smoothedData[i] ? _smoothingUp : _smoothingDown;
      _smoothedData[i] += (ampTarget - _smoothedData[i]) * ampFactor;

      // Signed waveform (0.0 = max negative, 0.5 = silence, 1.0 = max positive) — for line, helix
      final signedTarget = raw / 255.0;
      final signedFactor = (signedTarget - _signedData[i]).abs() > (_signedData[i] - 0.5).abs()
          ? _smoothingUp : _smoothingDown;
      _signedData[i] += (signedTarget - _signedData[i]) * signedFactor;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _updateAudioData();

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
            audioData: _smoothedData,
            color: widget.color,
            time: _controller.value,
          ),
          'radial' => RadialBurstVisualizer(
            audioData: _smoothedData,
            color: widget.color,
            time: _controller.value,
          ),
          'mirror_bars' => MirrorBarsVisualizer(
            audioData: _smoothedData,
            color: widget.color,
            time: _controller.value,
          ),
          'line' => WaveformLineVisualizer(
            audioData: _signedData,  // signed waveform for oscilloscope
            color: widget.color,
            time: _controller.value,
          ),
          'terrain' => TerrainVisualizer(
            audioData: _smoothedData,
            color: widget.color,
            time: _controller.value,
          ),
          'dots' => DotMatrixVisualizer(
            audioData: _smoothedData,
            color: widget.color,
            time: _controller.value,
          ),
          _ => CircularBarVisualizer(
            waveData: widget.audioData,
            height: widget.height,
            width: widget.width,
            color: widget.color,
          ),
        },
      ),
    );
  }
}
