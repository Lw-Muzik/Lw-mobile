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
          final raw = call.arguments['fft'];
          // Android sends byte[] → Uint8List; iOS sends FlutterStandardTypedData → Uint8List
          final List<int> samples = raw is List<int> ? raw : List<int>.from(raw);
          for (Function callback in _fftCallbacks) {
            callback(samples);
          }
          break;
        case 'onWaveformVisualization':
          final raw = call.arguments['waveform'];
          final List<int> samples = raw is List<int> ? raw : List<int>.from(raw);
          final int sampleRate = call.arguments['sampleRate'] as int;
          for (Function callback in _waveformCallbacks) {
            callback(samples, sampleRate);
          }
          break;
        default:
          // Don't throw — other method calls may arrive on this channel
          break;
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
