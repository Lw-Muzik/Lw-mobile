import 'package:flutter/scheduler.dart';
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
  bool _frameScheduled = false;

  @override
  void initState() {
    super.initState();
    _visualizer = Visualizers.audioVisualizer()..activate(widget.id);
    _visualizer!.addListener(
      waveformCallback: _onWaveform,
      fftCallback: _onFft,
    );
  }

  /// Coalesce FFT + waveform updates (which arrive on two separate streams,
  /// usually in different microtasks) into a single rebuild per frame instead
  /// of calling setState twice. Caps rebuilds at the display refresh rate and
  /// naturally pauses while backgrounded (no frames are produced).
  void _scheduleUpdate() {
    if (_frameScheduled || !mounted) return;
    _frameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frameScheduled = false;
      if (mounted) setState(() {});
    });
  }

  void _onWaveform(List<int> samples, int sampleRate) {
    if (!mounted) return;
    _waveData = samples;
    _sampleRate = sampleRate;
    _scheduleUpdate();
  }

  void _onFft(List<int> samples) {
    if (!mounted) return;
    _fftData = samples;
    _scheduleUpdate();
  }

  @override
  void dispose() {
    // Dispose (not just removeListener) so the EventChannel subscriptions this
    // instance opened in activate() are actually cancelled — otherwise every
    // teardown (e.g. on each track change) leaks a live native FFT tap.
    _visualizer?.dispose();
    _visualizer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _waveData, _fftData, _sampleRate);
  }
}
