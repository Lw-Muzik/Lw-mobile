// ignore_for_file: must_be_immutable, library_private_types_in_public_api

import 'package:flutter/widgets.dart';

import 'AudioVisualizer.dart';

class VisualizerWidget extends StatefulWidget {
  final Function(BuildContext context, List<int> fft) builder;
  int id;
  VisualizerWidget({super.key, required this.builder, required this.id});

  @override
  _VisualizerWidgetState createState() => _VisualizerWidgetState();
}

class _VisualizerWidgetState extends State<VisualizerWidget> {
  AudioVisualizer? visualizer;
  List<int> fft = const [];
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
      ..addListener(waveformCallback: (List<int> samples) {
        setState(() => fft = samples);
      });
    return widget.builder(context, fft);
  }
}
