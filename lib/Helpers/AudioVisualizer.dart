import 'package:eq_app/Helpers/Channel.dart';
import 'package:flutter/services.dart';

class Visualizers {
  static AudioVisualizer audioVisualizer() {
    return AudioVisualizer(
      channel: Channel.channel,
    );
  }

  static void enableVisual(bool enable) {
    Channel.channel.invokeMethod("enableVisual", {"enableVisual": enable});
  }

// scaleVisualizer
  static void scaleVisualizer(bool scale) async {
    await Channel.channel.invokeMethod("setScalingMode", {"scale": scale});
  }

  static void setFrameRate(int frameRate) async {
    await Channel.channel
        .invokeMethod("setFrameRate", {"frameRate": frameRate});
  }

  static Future<bool> getEnabled() async {
    return await Channel.channel.invokeMethod("getEnabled");
  }
}

class AudioVisualizer {
  final MethodChannel channel;
  final Set<FftCallback> _fftCallbacks = {};
  final Set<WaveformCallback> _waveformCallbacks = {};

  AudioVisualizer({
    required this.channel,
  }) {
    channel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'onFftVisualization':
          List<int> samples = call.arguments['fft'];
          for (Function callback in _fftCallbacks) {
            callback(samples);
          }
          break;
        case 'onWaveformVisualization':
          List<int> samples = call.arguments['waveform'];
          int sampleRate = call.arguments['sampleRate'];
          for (Function callback in _waveformCallbacks) {
            callback(samples, sampleRate);
          }
          break;
        default:
          throw UnimplementedError(
              '${call.method} is not implemented for audio visualization channel.');
      }
    });
  }
  void activate(int sessionID) {
    channel.invokeMethod('activate_visualizer', {"sessionID": sessionID});
  }

  void deactivate() {
    channel.invokeMethod('deactivate_visualizer');
  }

  void dispose() {
    deactivate();
    _fftCallbacks.clear();
    _waveformCallbacks.clear();
  }

  void addListener({
    FftCallback? fftCallback,
    WaveformCallback? waveformCallback,
  }) {
    if (null != fftCallback) {
      _fftCallbacks.add(fftCallback);
    }
    if (null != waveformCallback) {
      _waveformCallbacks.add(waveformCallback);
    }
  }

  void removeListener({
    FftCallback? fftCallback,
    WaveformCallback? waveformCallback,
  }) {
    if (null != fftCallback) {
      _fftCallbacks.remove(fftCallback);
    }
    if (null != waveformCallback) {
      _waveformCallbacks.remove(waveformCallback);
    }
  }
}

typedef FftCallback = void Function(List<int> fftSamples);
typedef WaveformCallback = void Function(
    List<int> waveformSamples, int sampleRate);
