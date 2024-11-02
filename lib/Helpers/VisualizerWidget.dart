// ignore_for_file: must_be_immutable

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
  // ignore: library_private_types_in_public_api
  _VisualizerWidgetState createState() => _VisualizerWidgetState();
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
    // visualizer?.dispose();
    super.dispose();
  }

  void _updateAudioData() {
    if (waveData.isEmpty) {
      _normalizedAudioData.fillRange(0, _normalizedAudioData.length, 0);
      return;
    }

    final inputLength = waveData.length;
    for (int i = 0; i < _normalizedAudioData.length; i++) {
      if (inputLength > 0) {
        final rawIndex =
            (i * inputLength / _normalizedAudioData.length).floor();
        final index = rawIndex.clamp(0, inputLength - 1);
        _normalizedAudioData[i] = waveData[index].abs() / 128.0;
      } else {
        _normalizedAudioData[i] = 0;
      }
      // log(_normalizedAudioData.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    // _updateAudioData();
    visualizer = Visualizers.audioVisualizer()
      ..activate(widget.id)
      ..addListener(waveformCallback: (samples, sampleRate) {
        setState(() => waveData = samples);
        setState(() => sampleRate = sampleRate);
      });

    return widget.builder(context, waveData, sampleRate);
  }
}
