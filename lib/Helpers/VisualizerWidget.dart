import 'package:flutter/widgets.dart';

import 'AudioVisualizer.dart';

class VisualizerWidget extends StatefulWidget {
  final Widget Function(BuildContext context, List<int> fft, int sampleRate)
      builder;

  final int id;
  const VisualizerWidget({
    super.key,
    required this.builder,
    required this.id,
  });

  @override
  State<VisualizerWidget> createState() => _VisualizerWidgetState();
}

class _VisualizerWidgetState extends State<VisualizerWidget> {
  AudioVisualizer? visualizer;
  int sampleRate = 0;
  List<int> waveData = const [];
  final List<double> _normalizedAudioData = List.filled(512, 0.0);
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    visualizer = Visualizers.audioVisualizer()
      ..activate(widget.id)
      ..addListener(waveformCallback: (samples, sampleRate) {
        setState(() => waveData = samples);
        setState(() => this.sampleRate = sampleRate);
      });

    return widget.builder(context, waveData, sampleRate);
  }
}
