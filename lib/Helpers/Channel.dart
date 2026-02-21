// ignore_for_file: constant_identifier_names
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Channel {
  static MethodChannel channel = const MethodChannel("eq_app");

  static Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      debugPrint('Channel error [$method]: ${e.message}');
      return null;
    } on MissingPluginException {
      debugPrint('Channel method not found: $method');
      return null;
    }
  }

  static Future<T> _invokeRequired<T>(String method, T fallback, [Map<String, dynamic>? args]) async {
    final result = await _invoke<T>(method, args);
    return result ?? fallback;
  }

  /// initializing Equalizer
  static void dispose() async {
    await _invoke("release");
  }

  static void showNativeMessage(String message) async {
    await _invoke("showNativeMessage", {"message": message});
  }

  static Future<List<Map<String, dynamic>>> getPreset() async {
    final result = await _invoke("getPresetNames");
    if (result == null) return [];
    List<String> p = (result as List).cast<String>();
    return List.generate(
        p.length, (index) => {"id": index, "preset": p[index]});
  }

  static void setPreset(String p) async {
    await _invoke("setPreset", {"preset": p});
  }

  static void setBandLevel(int band, int level) async {
    await _invoke("setBandLevel", {"band": band, "level": level});
  }

  static Future<List<int>> getBandLevelRange() async {
    final result = await _invoke("getBandLevelRange");
    if (result == null) return [0, 0];
    return (result as List).cast<int>();
  }

  static Future<int> getBandLevel(int band) async {
    return await _invokeRequired<int>("getBandLevel", 0, {"_band": band});
  }

  static Future<bool> isEnabled() async {
    return await _invokeRequired<bool>("isEnabled", false);
  }

  static Future<String> getSetting() async {
    return await _invokeRequired<String>("getSettings", "");
  }

  static void setEqSettings({int nBands = 5}) async {
    await _invoke("setSettings", {"nBands": nBands});
  }

  static Future<List<int>> getBandFreq() async {
    final result = await _invoke("getBandFreq");
    if (result == null) return [];
    return (result as List).cast<int>();
  }

  static void enableEq(bool enabled) async {
    await _invoke("enableEq", {"enable": enabled});
  }

  static void enableBass(bool enable) async {
    await _invoke("enableBassBoost", {"enableBass": enable});
  }

  static Future<bool> isBassEnabled() async {
    return await _invokeRequired<bool>("isBassEnabled", false);
  }

  static Future<int> getBassStrength() async {
    return await _invokeRequired<int>("bassBoostStrength", 0);
  }

  static void setBassStrength(int strength) async {
    await _invoke("setBassBoostStrength", {"strength": strength});
  }

  /// Loudness enhancer (session-aware init — used by both legacy and DVC)
  static void _initLoudnessEnhancer(int sessionId) async {
    await _invoke("initLoudnessEnhancer", {"sessionId": sessionId});
  }

  static void enableLoudnessEnhancer(bool enable) async {
    await _invoke("enableLoudnessEnhancer", {"enableLoud": enable});
  }

  /// Sets the target gain (millibels)
  static void setTargetGain(int strength) async {
    await _invoke("setLoudnessEnhancerStrength", {"strength": strength});
  }

  /// Retrieves the target gain value
  static Future<double> getTargetGain() async {
    return await _invokeRequired<double>("loudnessEnhancerStrength", 0.0);
  }

  // ==================== DVC (Direct Volume Control) ====================

  /// Enable DVC: saves system volume, maxes STREAM_MUSIC, enables LoudnessEnhancer
  static Future<void> enableDvc() async {
    await _invoke("enableDvc", {});
  }

  /// Disable DVC: restores saved system volume, disables LoudnessEnhancer
  static Future<void> disableDvc() async {
    await _invoke("disableDvc", {});
  }

  /// Set DVC gain in dB. Native side handles system volume crossover
  /// for true silence at the bottom of the range.
  static Future<void> setDvcGain(double dB) async {
    await _invoke("setDvcGain", {"gain": dB});
  }

  /// Get current DVC internal gain
  static Future<double> getDvcGain() async {
    return await _invokeRequired<double>("getDvcGain", 0.0);
  }

  /// Check if DVC is currently active
  static Future<bool> isDvcActive() async {
    return await _invokeRequired<bool>("isDvcActive", false);
  }

  /// Get current system music volume
  static Future<int> getSystemVolume() async {
    return await _invokeRequired<int>("getSystemVolume", 0);
  }

  /// Get maximum system music volume
  static Future<int> getSystemMaxVolume() async {
    return await _invokeRequired<int>("getSystemMaxVolume", 15);
  }

  /// EventChannel for hardware volume button events when DVC is active.
  /// Emits "up" or "down" strings.
  static const EventChannel _dvcVolumeButtonChannel =
      EventChannel("eq_app/dvc_volume_button");

  static Stream<String> get dvcVolumeButtonStream =>
      _dvcVolumeButtonChannel
          .receiveBroadcastStream()
          .map((event) => event.toString());

  // ==================== Custom DSP Room Effects ====================

  /// Enable/disable FDN reverb
  static Future<void> dspSetReverbEnabled(bool enabled) async {
    await _invoke("dspSetReverbEnabled", {"enabled": enabled});
  }

  /// Room size (0.0 - 1.0) — scales delay line lengths
  static Future<void> dspSetRoomSize(double value) async {
    await _invoke("dspSetRoomSize", {"value": value});
  }

  /// Decay (0.0 - 1.0) — maps to RT60 (0.1s - 15s)
  static Future<void> dspSetDecay(double value) async {
    await _invoke("dspSetDecay", {"value": value});
  }

  /// Damping (0.0 - 1.0) — feedback lowpass (0=bright, 1=dark)
  static Future<void> dspSetDamping(double value) async {
    await _invoke("dspSetDamping", {"value": value});
  }

  /// Pre-delay in ms (0 - 200)
  static Future<void> dspSetPreDelay(double ms) async {
    await _invoke("dspSetPreDelay", {"value": ms});
  }

  /// Diffusion (0.0 - 1.0) — echo density
  static Future<void> dspSetDiffusion(double value) async {
    await _invoke("dspSetDiffusion", {"value": value});
  }

  /// Reverb wet/dry mix (0.0 - 1.0)
  static Future<void> dspSetReverbWetDry(double value) async {
    await _invoke("dspSetReverbWetDry", {"value": value});
  }

  /// Enable/disable M/S stereo expansion
  static Future<void> dspSetStereoExpandEnabled(bool enabled) async {
    await _invoke("dspSetStereoExpandEnabled", {"enabled": enabled});
  }

  /// Stereo width (0.0 = mono, 1.0 = normal, 2.0 = max expansion)
  static Future<void> dspSetStereoWidth(double value) async {
    await _invoke("dspSetStereoWidth", {"value": value});
  }

  /// Enable/disable BS2B crossfeed
  static Future<void> dspSetCrossfeedEnabled(bool enabled) async {
    await _invoke("dspSetCrossfeedEnabled", {"enabled": enabled});
  }

  /// Set crossfeed filter params (cutoffHz: 100-2000, feedLevelDb: 1-15)
  static Future<void> dspSetCrossfeedParams(double cutoffHz, double feedLevelDb) async {
    await _invoke("dspSetCrossfeedParams", {"cutoff": cutoffHz, "feed": feedLevelDb});
  }
  /// Initialize DSP engine
  static void _initDSPEngine(int audioSessionId) async {
    await _invoke("initDSPEngine", {"dspId": audioSessionId});
  }

  static void enableDSPEngine(bool enable) async {
    await _invoke("enableDSP", {"enableEngine": enable});
  }


  static Future<double> setDSPVolume(double v) async {
    return await _invokeRequired<double>("setDSPVolume", 0.0, {"dspVolume": v});
  }

  static void setDspNoiseThreshold(double noiseValue) async {
    await _invoke("setDspNoiseThreshold", {"noiseThreshold": noiseValue});
  }

  static void setTunerBass(double value) async {
    await _invoke("setTunerBass", {"tunerBass": value});
  }

  static void setDSPXBass(double bass) async {
    await _invoke("setDSPXBass", {"xBass": bass});
  }

  static void setDSPPowerBass(double bass) async {
    await _invoke("setDSPPowerBass", {"powerBass": bass});
  }

  static void setDSPTreble(double treble) async {
    await _invoke("setDSPXTreble", {"trebleGain": treble});
  }

  // ----------- DSP compressor (MBC) ------------------

  static void setDspKneeWidth(double kneeWidth) async {
    await _invoke("kneeWidth", {"kneeWidth": kneeWidth});
  }

  static void setPreGain(double preGain) async {
    await _invoke("setPreGain", {"preGain": preGain});
  }

  static void setDspExpandRatio(double expandRatio) async {
    await _invoke("expandRatio", {"expandRatio": expandRatio});
  }

  // -------------- end of compressor settings ---------------------

  static void setDSPSpeakers(
      List<dynamic> speakers, List<double> levels) async {
    Map<String, dynamic> dsps = {"speakers": speakers, "levels": levels};
    await _invoke("setDSPSpeakers", {"spks": dsps});
    final prefs = await SharedPreferences.getInstance();
    prefs.setString("dsp_speaker", json.encode(dsps));
  }

  static void disposeDSP() async {
    await _invoke("disposeDSP");
  }

  static void setCutOffFreq(int freq) async {
    await _invoke("setCutOffFreq", {"tunerBassFreq": freq});
  }

  static Future<double> getVocalLevel() async {
    return await _invokeRequired<double>("getVocalLevel", 0.0);
  }

  static void deleteManager(String path) async {
    await _invoke("deleteManager", {"filePath": path});
  }

  // ==================== 32-Band Graphic EQ (Pre-EQ) ====================

  static Future<void> setGraphicBandGain(int band, double gain) async {
    await _invoke("setGraphicBandGain", {"band": band, "gain": gain});
  }

  static Future<double> getGraphicBandGain(int band) async {
    return await _invokeRequired<double>("getGraphicBandGain", 0.0, {"band": band});
  }

  static Future<void> setGraphicAllBands(List<double> gains) async {
    await _invoke("setGraphicAllBands", {"gains": gains});
  }

  static Future<List<double>> getGraphicAllBands() async {
    final result = await _invoke("getGraphicAllBands");
    if (result == null) return List.filled(32, 0.0);
    return (result as List).map((e) => (e as num).toDouble()).toList();
  }

  // ==================== 32-Band Parametric EQ (Post-EQ) ====================

  static Future<void> setParametricBand(int band, double freq, double gain) async {
    await _invoke("setParametricBand", {"band": band, "freq": freq, "gain": gain});
  }

  static Future<void> setParametricAllBands(List<double> freqs, List<double> gains) async {
    await _invoke("setParametricAllBands", {"freqs": freqs, "gains": gains});
  }

  // ==================== Preamp ====================

  static Future<void> setPreamp(double gain) async {
    await _invoke("setPreamp", {"gain": gain});
  }

  static Future<double> getPreamp() async {
    return await _invokeRequired<double>("getPreamp", 0.0);
  }

  // ==================== MBC Toggle ====================

  static Future<void> enableMbc(bool enable) async {
    await _invoke("enableMbc", {"enable": enable});
  }

  static Future<bool> isMbcEnabled() async {
    return await _invokeRequired<bool>("isMbcEnabled", false);
  }


  // ==================== Device Detection ====================

  static Future<bool> isDynamicsProcessingAvailable() async {
    return await _invokeRequired<bool>("isDynamicsProcessingAvailable", false);
  }

  static Future<String> getAudioOutputType() async {
    return await _invokeRequired<String>("getAudioOutputType", "speaker");
  }

  static void setSessionId(int sessionId) async {
    _initDSPEngine(sessionId);
    _initLoudnessEnhancer(sessionId);
    // "init" still routes to DSPEngine on native side (CustomEq removed)
    await _invoke("init", {"sessionId": sessionId});
  }

  // ==================== Lyrics ====================

  /// Reads embedded USLT lyrics from an MP3 file via mp3agic native.
  static Future<String?> readLyrics(String filePath) async {
    return await _invoke<String>("readLyrics", {"filePath": filePath});
  }

  /// Writes lyrics text into the ID3v2 USLT frame of an MP3 file.
  static Future<bool> writeLyrics(String filePath, String lyrics) async {
    return await _invokeRequired<bool>(
      "writeLyrics",
      false,
      {"filePath": filePath, "lyrics": lyrics},
    );
  }
}
