import 'package:eq_app/Visualizers/cube_visualizer.dart';
import 'package:flutter/material.dart';

import 'CircularBarVisualizer.dart';
import 'fabric_visualizer.dart';
import 'plasma_visualiser.dart';
import 'ripple_visualizer.dart';
import 'sea-visualizer.dart';
import 'spectrum-visualiser.dart';
import 'sphere_visualizer.dart';

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
  final List<double> _smoothedData = List.filled(512, 0.0);

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
      // Decay to silence smoothly
      for (int i = 0; i < _smoothedData.length; i++) {
        _smoothedData[i] += (0.0 - _smoothedData[i]) * _smoothingDown;
      }
      return;
    }

    final inputLength = widget.audioData.length;
    for (int i = 0; i < _smoothedData.length; i++) {
      final rawIndex =
          (i * inputLength / _smoothedData.length).floor().clamp(0, inputLength - 1);
      final target = widget.audioData[rawIndex].abs() / 128.0;

      // Attack / decay envelope — rise fast on beats, fall slowly
      final factor = target > _smoothedData[i] ? _smoothingUp : _smoothingDown;
      _smoothedData[i] += (target - _smoothedData[i]) * factor;
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
    return CustomPaint(
      size: Size(widget.width, widget.height),
      painter: switch (selector) {
        'sphere' => SphereVisualizer(
            audioData: _smoothedData,
            time: _controller.value,
          ),
        'flower' => PlasmaVisualizer(
            audioData: _smoothedData,
            time: _controller.value,
          ),
        'fabric' => FabricVisualizer(
            audioData: _smoothedData,
            time: _controller.value,
          ),
        'bars' => SpectrumVisualizer(
            audioData: _smoothedData,
            color: widget.color,
            time: _controller.value,
          ),
        'sea' => OceanVisualizer(
            audioData: _smoothedData,
            time: _controller.value,
            color: widget.color,
          ),
        'circular' => CircularBarVisualizer(
            waveData: widget.audioData,
            height: widget.height,
            width: widget.width,
            color: widget.color,
          ),
        'cube' => CubeVisualizer(
            audioData: _smoothedData,
            time: _controller.value,
            color: widget.color,
          ),
        _ => RippleVisualizer(
            audioData: _smoothedData,
            time: _controller.value,
            color: widget.color,
          ),
      },
    );
  }
}
