import 'package:flutter/widgets.dart';

import 'AudioVisualizer.dart';

class VisualizerWidget extends StatefulWidget {
  final Widget Function(BuildContext context, List<int> fft, int sampleRate)
      builder;

  final int id;
  const VisualizerWidget({super.key, required this.builder, required this.id});

  @override
  State<VisualizerWidget> createState() => _VisualizerWidgetState();
}

class _VisualizerWidgetState extends State<VisualizerWidget> {
  AudioVisualizer? _visualizer;
  int _sampleRate = 0;
  List<int> _waveData = const [];

  @override
  void initState() {
    super.initState();
    _visualizer = Visualizers.audioVisualizer()..activate(widget.id);
    _visualizer!.addListener(
      waveformCallback: _onWaveform,
    );
  }

  void _onWaveform(List<int> samples, int sampleRate) {
    if (!mounted) return;
    setState(() {
      _waveData = samples;
      _sampleRate = sampleRate;
    });
  }

  @override
  void dispose() {
    _visualizer?.removeListener(waveformCallback: _onWaveform);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _waveData, _sampleRate);
  }
}
