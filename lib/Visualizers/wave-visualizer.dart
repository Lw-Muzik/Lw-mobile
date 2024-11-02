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

  const WaveVisualizer({
    super.key,
    required this.audioData,
    required this.width,
    required this.height,
    this.selector = "sphere",
  });

  @override
  State<WaveVisualizer> createState() => _WaveVisualizerState();
}

class _WaveVisualizerState extends State<WaveVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<double> _normalizedAudioData = List.filled(512, 0.0);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    _controller.repeat();
  }

  void _updateAudioData() {
    if (widget.audioData.isEmpty) {
      _normalizedAudioData.fillRange(0, _normalizedAudioData.length, 0.0);
      return;
    }
    final inputLength = widget.audioData.length;
    for (int i = 0; i < _normalizedAudioData.length; i++) {
      if (inputLength > 0) {
        final rawIndex =
            (i * inputLength / _normalizedAudioData.length).floor();
        final index = rawIndex.clamp(0, inputLength - 1);
        _normalizedAudioData[i] = widget.audioData[index].abs() / 128.0;
      } else {
        _normalizedAudioData[i] = 0.0;
      }
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
        return _buildFallbackVisualizer(widget.selector);
      },
    );
  }

  Widget _buildFallbackVisualizer(String selector) {
    // Simple fallback visualization when shader isn't loaded
    return CustomPaint(
      size: Size(widget.width, widget.height),
      painter: selector == 'sphere'
          ? SphereVisualizer(
              audioData: _normalizedAudioData,
              time: _controller.value,
            )
          : selector == 'flower'
              ? PlasmaVisualizer(
                  audioData: _normalizedAudioData,
                  time: _controller.value,
                )
              : selector == 'fabric'
                  ? FabricVisualizer(
                      audioData: _normalizedAudioData, time: _controller.value)
                  : selector == 'bars'
                      ? SpectrumVisualizer(
                          audioData: _normalizedAudioData,
                          time: _controller.value)
                      : selector == 'sea'
                          ? OceanVisualizer(
                              audioData: _normalizedAudioData,
                              time: _controller.value,
                            )
                          : selector == 'circular'
                              ? CircularBarVisualizer(
                                  waveData: widget.audioData,
                                  height: widget.height,
                                  width: widget.width,
                                  color: Colors.white,
                                )
                              : RippleVisualizer(
                                  audioData: _normalizedAudioData,
                                  time: _controller.value),
    );
  }
}
