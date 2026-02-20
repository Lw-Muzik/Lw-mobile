// ignore_for_file: constant_identifier_names
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PresetReverb {
  SMALL_ROOM,
  LARGE_ROOM,
  PRESET_PLATE,
  NONE,
  MEDIUM_ROOM,
  MEDIUM_HALL,
  LARGE_HALL,
  PRESET,
  CONCERT,
  SCENE,
  PRESET_ARENA
}

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

  /// Virtualizer
  static void _initVirtualizer(int sessionId) async {
    await _invoke("initVirtualizer", {"sessionId": sessionId});
  }

  static void enableVirtualizer(bool enable) async {
    await _invoke("enableVirtualizer", {"enable": enable});
  }

  static Future<bool> getVirtualizerEnabled() async {
    return await _invokeRequired<bool>("getVirtualEnabled", false);
  }

  static Future<int> forceVirtualization() async {
    return await _invokeRequired<int>("forceVirtualization", 0);
  }

  static void setVirtualizerStrength(int strength) async {
    await _invoke("setVirtualizerStrength", {"strength": strength});
  }

  static Future<int> getVirtualizerStrength() async {
    return await _invokeRequired<int>("virtualizerStrength", 0);
  }

  /// Loudness enhancer
  static void _initLoudnessEnhancer(int sessionId) async {
    await _invoke("initLoudnessEnhancer", {"sessionId": sessionId});
  }

  static void enableLoudnessEnhancer(bool enable) async {
    await _invoke("enableLoudnessEnhancer", {"enableLoud": enable});
  }

  /// Sets the target gain
  static void setTargetGain(int strength) async {
    await _invoke("setLoudnessEnhancerStrength", {"strength": strength});
  }

  /// Retrieves the target gain value
  static Future<double> getTargetGain() async {
    return await _invokeRequired<double>("loudnessEnhancerStrength", 0.0);
  }

  // Reverb effects
  static void _initReverb(int sessionId) async {
    await _invoke("initReverb", {"sessionId": sessionId});
  }

  /// Turns on the reverb effect
  static void enableReverb(bool enable) async {
    await _invoke("enableRoomEffects", {"enableEffects": enable});
  }

  /// Check if reverb is enabled
  static Future<bool> isReverbEnabled() async {
    return await _invokeRequired<bool>("isEffectEnabled", false);
  }

  /// The valid range is [100, 20000].
  static void setDecayTime(int decayTime) async {
    await _invoke("setDecayTime", {"decayTime": decayTime});
  }

  /// The valid range is [100, 20000].
  static Future<int> getDecayTime() async {
    return await _invokeRequired<int>("getDecayTime", 0);
  }

  /// The valid range is [0, 1000].
  static void setDensity(int density) async {
    await _invoke("setDensity", {"density": density});
  }

  /// The valid range is [0, 1000].
  static Future<int> getDensity() async {
    return await _invokeRequired<int>("getDensity", 0);
  }

  /// The diffusion valid range is [0, 1000]
  static void setDiffusion(int diffusion) async {
    await _invoke("setDiffusion", {"diffusion": diffusion});
  }

  /// The diffusion valid range is [0, 1000]
  static Future<int> getDiffusion() async {
    return await _invokeRequired<int>("getDiffusion", 0);
  }

  /// Reflects delay valid range is [0, 300].
  static void setReflectionsDelay(int reflectionsDelay) async {
    await _invoke("setReflectionsDelay", {"reflectionsDelay": reflectionsDelay});
  }

  /// Reflects delay valid range is [0, 300].
  static Future<int> getReflectionsDelay() async {
    return await _invokeRequired<int>("getReflectionsDelay", 0);
  }

  /// Reverb delay valid range is [0, 100].
  static void setReverbDelay(int reverbDelay) async {
    await _invoke("setReverbDelay", {"reverbDelay": reverbDelay});
  }

  /// Reverb delay valid range is [0, 100].
  static Future<int> getReverbDelay() async {
    return await _invokeRequired<int>("getReverbDelay", 0);
  }

  /// Reverb level valid range is [-9000, 2000].
  static void setReverbLevel(int reverbLevel) async {
    await _invoke("setReverbLevel", {"reverbLevel": reverbLevel});
  }

  static Future<int> getReverbLevel() async {
    return await _invokeRequired<int>("getReverbLevel", 0);
  }

  /// Room level valid range is [-9000, 0]. Master knob for reverb.
  static void setRoomLevel(int roomLevel) async {
    await _invoke("setRoomLevel", {"roomLevel": roomLevel});
  }

  /// Room level valid range is [-9000, 0]. Master knob for reverb.
  static Future<int> getRoomLevel() async {
    return await _invokeRequired<int>("getRoomLevel", 0);
  }

  /// Room HF level valid range is [-9000, 0].
  static void setRoomHFLevel(int roomHFLevel) async {
    await _invoke("setRoomHFLevel", {"roomHFLevel": roomHFLevel});
  }

  /// Room HF level valid range is [-9000, 0].
  static Future<int> getRoomHFLevel() async {
    return await _invokeRequired<int>("getRoomHFLevel", 0);
  }

  /// Decay HF ratio valid range is [100, 2000].
  static void setDecayHFRatio(int decayHFLevel) async {
    await _invoke("setDecayHFRatio", {"decayHFRatio": decayHFLevel});
  }

  /// Decay HF ratio valid range is [100, 2000].
  static Future<int> getDecayHFRatio() async {
    return await _invokeRequired<int>("getDecayHFRatio", 0);
  }

  /// Reflections level valid range is [-9000, 1000]
  static void setReflectionsDelayLevel(int reflectionsLevel) async {
    await _invoke("setReflectionsLevel", {"reflectionsLevel": reflectionsLevel});
  }

  /// Reflections level valid range is [-9000, 1000]
  static Future<int> getReflectionsLevel() async {
    return await _invokeRequired<int>("getReflectionsLevel", 0);
  }

  /// Initialize DSP engine
  static void _initDSPEngine(int audioSessionId) async {
    await _invoke("initDSPEngine", {"dspId": audioSessionId});
  }

  static void enableDSPEngine(bool enable) async {
    await _invoke("enableDSP", {"enableEngine": enable});
  }

  static void setOutGain(double limit) async {
    await _invoke("setOutGain", {"outGain": limit});
  }

  static Future<double> getOutGain() async {
    return await _invokeRequired<double>("getOutGain", 0.0);
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

  // ----------- DSP compressor ------------------

  static void setDSPThreshold(double threshold) async {
    await _invoke("setThreshold", {"dspThreshold": threshold});
  }

  static void setRatio(double ratio) async {
    await _invoke("setRatio", {"ratio": ratio});
  }

  static void setAttackTime(double attackTime) async {
    await _invoke("setAttackTime", {"attackTime": attackTime});
  }

  static void setReleaseTime(double release) async {
    await _invoke("setReleaseTime", {"releaseTime": release});
  }

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

  static void _initPresetReverb(int sessionId) async {
    await _invoke("initPresetReverb", {"priorityId": sessionId});
  }

  static Future<int> enablePresetReverb(bool enable) async {
    return await _invokeRequired<int>("enablePresetReverb", 0, {"enablePreset": enable});
  }

  static void setCutOffFreq(int freq) async {
    await _invoke("setCutOffFreq", {"tunerBassFreq": freq});
  }

  static Future<double> getVocalLevel() async {
    return await _invokeRequired<double>("getVocalLevel", 0.0);
  }

  static void setReverbPreset(PresetReverb preset) async {
    final presetMap = {
      PresetReverb.NONE: 0,
      PresetReverb.SMALL_ROOM: 1,
      PresetReverb.MEDIUM_ROOM: 2,
      PresetReverb.LARGE_ROOM: 3,
      PresetReverb.MEDIUM_HALL: 4,
      PresetReverb.LARGE_HALL: 5,
      PresetReverb.PRESET_PLATE: 6,
      PresetReverb.CONCERT: 7,
      PresetReverb.SCENE: 8,
      PresetReverb.PRESET_ARENA: 9,
      PresetReverb.PRESET: 0,
    };
    await _invoke("chooseEffectPreset", {"effectPreset": presetMap[preset] ?? 0});
  }

  static Future<bool> isAndroid11() async {
    return await _invokeRequired<bool>("isAndroid11", false);
  }

  static Future<int> getReverbPreset() async {
    return await _invokeRequired<int>("getReverbPreset", 0);
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

  // ==================== Device Detection ====================

  static Future<bool> isDynamicsProcessingAvailable() async {
    return await _invokeRequired<bool>("isDynamicsProcessingAvailable", false);
  }

  static Future<String> getAudioOutputType() async {
    return await _invokeRequired<String>("getAudioOutputType", "speaker");
  }

  static void setSessionId(int sessionId) async {
    _initVirtualizer(sessionId);
    _initReverb(sessionId);
    _initDSPEngine(sessionId);
    _initPresetReverb(sessionId);
    _initLoudnessEnhancer(sessionId);
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
