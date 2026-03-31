import 'dart:io';
import 'dart:typed_data';

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

  static void scaleVisualizer(bool scale) async {
    await Channel.channel.invokeMethod("setScalingMode", {"scale": scale});
  }

  static void setFrameRate(int frameRate) async {
    await Channel.channel
        .invokeMethod("setFrameRate", {"frameRate": frameRate});
  }

  /// Set C++ FFT smoothing rates. Attack = how fast bands rise, decay = how fast they fall.
  static void setSmoothing(double attack, double decay) async {
    await Channel.channel
        .invokeMethod("setVizSmoothing", {"attack": attack, "decay": decay});
  }

  /// Set FFT gain / beat sensitivity. 0.5 = subtle, 1.0 = normal, 3.0 = intense.
  static void setGain(double gain) async {
    await Channel.channel.invokeMethod("setVizGain", {"gain": gain});
  }

  static Future<bool> getEnabled() async {
    return await Channel.channel.invokeMethod("getEnabled");
  }
}

/// Unified audio visualizer that uses:
///   - Android: Custom C++ FFT via ExoPlayer AudioProcessor tap (no audio session ID)
///   - iOS: MTAudioProcessingTap + vDSP FFT via MethodChannel (existing)
class AudioVisualizer {
  final MethodChannel channel;
  final Set<FftCallback> _fftCallbacks = {};
  final Set<WaveformCallback> _waveformCallbacks = {};
  final Set<FftBandsCallback> _bandsCallbacks = {};

  // Android EventChannels for C++ FFT pipeline
  static const EventChannel _fftBandsChannel = EventChannel('eq_app/fft_bands');
  static const EventChannel _waveformChannel = EventChannel('eq_app/waveform');

  // Active stream subscriptions
  dynamic _bandsSub;
  dynamic _waveSub;

  AudioVisualizer({
    required this.channel,
  }) {
    // iOS: keep the existing MethodChannel callbacks
    channel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'onFftVisualization':
          final raw = call.arguments['fft'];
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
          break;
      }
    });
  }

  void activate(int sessionID) {
    if (Platform.isAndroid) {
      // Android: start C++ FFT pipeline via EventChannel subscription
      _bandsSub = _fftBandsChannel.receiveBroadcastStream().listen((data) {
        if (data == null) return;
        final Float32List bands;
        if (data is Float32List) {
          bands = data;
        } else if (data is List) {
          bands = Float32List.fromList(data.cast<double>());
        } else {
          return;
        }
        for (final cb in _bandsCallbacks) {
          cb(bands);
        }
        // Also convert to List<int> for legacy FFT painters
        // Map float [0.0-1.0] to int [0-255] for compatibility
        final legacyFft = List<int>.generate(
          bands.length * 2,
          (i) => i.isEven ? (bands[i ~/ 2] * 255).round().clamp(0, 255) : 0,
        );
        for (final cb in _fftCallbacks) {
          cb(legacyFft);
        }
      });
      _waveSub = _waveformChannel.receiveBroadcastStream().listen((data) {
        if (data == null) return;
        final List<int> waveform;
        if (data is Uint8List) {
          waveform = data.toList();
        } else if (data is List) {
          // byte[] from Android arrives as signed bytes
          waveform = List<int>.generate(
            data.length,
            (i) => ((data[i] as int) + 128) & 0xFF, // signed → unsigned
          );
        } else {
          return;
        }
        for (final cb in _waveformCallbacks) {
          cb(waveform, 44100);
        }
      });
    } else {
      // iOS: use existing Visualizer API via MethodChannel
      channel.invokeMethod('activate_visualizer', {"sessionID": sessionID});
    }
  }

  void deactivate() {
    if (Platform.isAndroid) {
      _bandsSub?.cancel();
      _bandsSub = null;
      _waveSub?.cancel();
      _waveSub = null;
    } else {
      channel.invokeMethod('deactivate_visualizer');
    }
  }

  void dispose() {
    deactivate();
    _fftCallbacks.clear();
    _waveformCallbacks.clear();
    _bandsCallbacks.clear();
  }

  void addListener({
    FftCallback? fftCallback,
    WaveformCallback? waveformCallback,
    FftBandsCallback? bandsCallback,
  }) {
    if (null != fftCallback) {
      _fftCallbacks.add(fftCallback);
    }
    if (null != waveformCallback) {
      _waveformCallbacks.add(waveformCallback);
    }
    if (null != bandsCallback) {
      _bandsCallbacks.add(bandsCallback);
    }
  }

  void removeListener({
    FftCallback? fftCallback,
    WaveformCallback? waveformCallback,
    FftBandsCallback? bandsCallback,
  }) {
    if (null != fftCallback) {
      _fftCallbacks.remove(fftCallback);
    }
    if (null != waveformCallback) {
      _waveformCallbacks.remove(waveformCallback);
    }
    if (null != bandsCallback) {
      _bandsCallbacks.remove(bandsCallback);
    }
  }
}

typedef FftCallback = void Function(List<int> fftSamples);
typedef WaveformCallback = void Function(
    List<int> waveformSamples, int sampleRate);
/// Pre-computed log-frequency bands (64 floats, 0.0-1.0) from C++ FFT.
typedef FftBandsCallback = void Function(Float32List bands);
