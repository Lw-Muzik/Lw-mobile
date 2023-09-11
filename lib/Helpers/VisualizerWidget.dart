// ignore_for_file: must_be_immutable, library_private_types_in_public_api

import 'package:flutter/widgets.dart';

import 'AudioVisualizer.dart';

class VisualizerWidget extends StatefulWidget {
  final Widget Function(BuildContext context, List<int> fft, int sampleRate)
      builder;

  int id;
  VisualizerWidget({
    super.key,
    required this.builder,
    required this.id,
  });

  @override
  _VisualizerWidgetState createState() => _VisualizerWidgetState();
}

class _VisualizerWidgetState extends State<VisualizerWidget> {
  AudioVisualizer? visualizer;
  int sampleRate = 0;
  List<int> waveData = const [];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    // visualizer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    visualizer = Visualizers.audioVisualizer()
      ..activate(widget.id)
      ..addListener(waveformCallback: (samples, sampleRate) {
        setState(() => waveData = samples);
        setState(() => sampleRate = sampleRate);
      });

    return widget.builder(context, waveData, sampleRate);
  }
}
