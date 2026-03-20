import 'package:flutter/widgets.dart';

import 'AudioVisualizer.dart';

class VisualizerWidget extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    List<int> waveform,
    List<int> fft,
    int sampleRate,
  ) builder;

  final int id;
  const VisualizerWidget({super.key, required this.builder, required this.id});

  @override
  State<VisualizerWidget> createState() => _VisualizerWidgetState();
}

class _VisualizerWidgetState extends State<VisualizerWidget> {
  AudioVisualizer? _visualizer;
  int _sampleRate = 0;
  List<int> _waveData = const [];
  List<int> _fftData = const [];

  @override
  void initState() {
    super.initState();
    _visualizer = Visualizers.audioVisualizer()..activate(widget.id);
    _visualizer!.addListener(
      waveformCallback: _onWaveform,
      fftCallback: _onFft,
    );
  }

  void _onWaveform(List<int> samples, int sampleRate) {
    if (!mounted) return;
    setState(() {
      _waveData = samples;
      _sampleRate = sampleRate;
    });
  }

  void _onFft(List<int> samples) {
    if (!mounted) return;
    // Update FFT data — setState ensures WaveVisualizer sees it
    setState(() {
      _fftData = samples;
    });
  }

  @override
  void dispose() {
    _visualizer?.removeListener(
      waveformCallback: _onWaveform,
      fftCallback: _onFft,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _waveData, _fftData, _sampleRate);
  }
}
