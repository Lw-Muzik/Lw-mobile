// ignore_for_file: constant_identifier_names

import 'dart:developer';

import 'package:flutter/services.dart';

enum PresetReverb {
  SMALL_ROOM,
  LARGE_ROOM,
  PRESET_PLATE,
  NONE,
  MEDIUM_ROOM,
  MEDIUM_HALL,
  LARGE_HALL,
  PRESET
}

class Channel {
  static MethodChannel channel = const MethodChannel("eq_app");

  /// initializing Equalizer

  static void dispose() async {
    await channel.invokeMethod("release");
  }

  static Future<List<Map<String, dynamic>>> getPreset() async {
    List<String> p =
        (await channel.invokeMethod("getPresetNames")).cast<String>();
    return List.generate(
        p.length, (index) => {"id": index, "preset": p[index]});
  }

  static void setPreset(String p) async {
    await channel.invokeMethod("setPreset", {"preset": p});
  }

  static void setBandLevel(int band, int level) async {
    await channel
        .invokeMethod("setBandLevel", {"band": band, "level": (level)});
  }

  static Future<List<int>> getBandLevelRange() async {
    return (await channel.invokeMethod("getBandLevelRange")).cast<int>();
  }

  static Future<int> getBandLevel(int band) async {
    int level = await channel.invokeMethod("getBandLevel", {"_band": band});
    return level;
  }

  static Future<bool> isEnabled() async {
    return await channel.invokeMethod("isEnabled");
  }

  static Future<String> getSetting() async {
    return await channel.invokeMethod("getSettings");
  }

  static void setEqSettings({int nBands = 5}) async {
    await channel.invokeMethod("setSettings", {"nBands": nBands});
  }

  static Future<List<int>> getBandFreq() async {
    List<int> freq = (await channel.invokeMethod("getBandFreq")).cast<int>();
    return freq;
  }

  static void enableEq(bool enabled) async {
    await channel.invokeMethod("enableEq", {"enable": enabled});
  }

  /// initializing bass boost
  @Deprecated("nolonger used")
  static void _initBassBoost(int sessionId) async {
    await channel.invokeMethod("initBassBoost", {"sessionId": sessionId});
  }

  @Deprecated("nolonger used")
  static void enableBass(bool enable) async {
    await channel.invokeMethod("enableBassBoost", {"enableBass": enable});
  }

  @Deprecated("nolonger used")
  static Future<bool> isBassEnabled() async {
    return (await channel.invokeMethod("isBassEnabled"));
  }

  @Deprecated("nolonger used")
  static Future<int> getBassStrength() async {
    return await channel.invokeMethod("bassBoostStrength");
  }

  static void setBassStrength(int strength) async {
    await channel.invokeMethod("setBassBoostStrength", {"strength": strength});
  }

  /// Virtualizer
  static void _initVirtualizer(int sessionId) async {
    await channel.invokeMethod("initVirtualizer", {"sessionId": sessionId});
  }

  static void enableVirtualizer(bool enable) async {
    await channel.invokeMethod("enableVirtualizer", {"enable": enable});
  }

  static Future<bool> getVirtualizerEnabled() async {
    return await channel.invokeMethod("getVirtualEnabled");
  }

  static Future<int> forceVirtualization() async {
    return await channel.invokeMethod("forceVirtualization");
  }

  static void setVirtualizerStrength(int strength) async {
    await channel
        .invokeMethod("setVirtualizerStrength", {"strength": strength});
  }

  static Future<int> getVirtualizerStrength() async {
    return (await channel.invokeMethod("virtualizerStrength"));
  }

  /// Loudness
  @Deprecated("nolonger used")
  static void _initLoudnessEnhancer(int sessionId) async {
    await channel
        .invokeMethod("initLoudnessEnhancer", {"sessionId": sessionId});
  }

  @Deprecated("nolonger used")
  static void enableLoudnessEnhancer(bool enable) async {
    await channel
        .invokeMethod("enableLoudnessEnhancer", {"enableLoud": enable});
  }

  /// Sets the target gain
  @Deprecated("nolonger used")
  static void setTargetGain(int strength) async {
    await channel
        .invokeMethod("setLoudnessEnhancerStrength", {"strength": strength});
  }

  /// retrieves the target gain value
  @Deprecated("nolonger used")
  static Future<double> getTargetGain() async {
    return (await channel.invokeMethod("loudnessEnhancerStrength"));
  }

  // Reverb effects
  static void _initReverb(int sessionId) async {
    await channel.invokeMethod("initReverb", {"sessionId": sessionId});
  }

  /// Turns on the reverb effect
  static void enableReverb(bool enable) async {
    await channel.invokeMethod("enableReverb", {"enableReverb": enable});
  }

  /// check if reverb is enabled
  static Future<bool> isReverbEnabled() async {
    return (await channel.invokeMethod("isReverbEnabled"));
  }

  ///  The valid range is [100, 20000].
  static void setDecayTime(int decayTime) async {
    await channel.invokeMethod("setDecayTime", {"decayTime": decayTime});
  }

  ///  The valid range is [100, 20000].
  static Future<int> getDecayTime() async {
    return (await channel.invokeMethod("getDecayTime"));
  }

  /// The valid range is [0, 1000].
  static void setDensity(int density) async {
    await channel.invokeMethod("setDensity", {"density": density});
  }

  /// The valid range is [0, 1000].
  static Future<int> getDensity() async {
    return (await channel.invokeMethod("getDensity"));
  }

  /// The diffusion valid range is [0, 1000]
  static void setDiffusion(int diffusion) async {
    await channel.invokeMethod("setDiffusion", {"diffusion": diffusion});
  }

  /// The diffusion valid range is [0, 1000]
  static Future<int> getDiffusion() async {
    return (await channel.invokeMethod("getDensity"));
  }

  /// reflects delay valid range is [0, 300].
  static void setReflectionsDelay(int reflectionsDelay) async {
    await channel.invokeMethod(
        "setReflectionsDelay", {"reflectionsDelay": reflectionsDelay});
  }

  /// reflects delay valid range is [0, 300].
  static Future<int> getReflectionsDelay() async {
    return (await channel.invokeMethod("getReflectionsDelay"));
  }

  /// Reverb delay  valid range is [0, 100].
  static void setReverbDelay(int reverbDelay) async {
    await channel.invokeMethod("setReverbDelay", {"reverbDelay": reverbDelay});
  }

  /// Reverb delay  valid range is [0, 100].
  static Future<int> getReverbDelay() async {
    return (await channel.invokeMethod("getReverbDelay"));
  }

  /// reverb level valid range is [-9000, 2000].
  static void setReverbLevel(int reverbDelay) async {
    await channel.invokeMethod("setReverbLevel", {"reverbLevel": reverbDelay});
  }

  static Future<int> getReverbLevel() async {
    return (await channel.invokeMethod("getReverbLevel"));
  }

  /// room level valid range is [-9000, 0]. master knob for reverb
  static void setRoomLevel(int roomLevel) async {
    await channel.invokeMethod("setRoomLevel", {"roomLevel": roomLevel});
  }

  /// room level valid range is [-9000, 0]. master knob for reverb
  static Future<int> getRoomLevel() async {
    return (await channel.invokeMethod("getRoomLevel"));
  }

  /// room HL level valid range is [-9000, 0].
  static void setRoomHFLevel(int roomHFLevel) async {
    await channel.invokeMethod("setRoomHFLevel", {"roomHFLevel": roomHFLevel});
  }

  /// room HL level valid range is [-9000, 0].
  static Future<int> getRoomHFLevel() async {
    return (await channel.invokeMethod("getRoomHFLevel"));
  }

  /// decay HF ratio The valid range is [100, 2000].
  static void setDecayHFRatio(int decayHFLevel) async {
    await channel
        .invokeMethod("setDecayHFRatio", {"decayHFRatio": decayHFLevel});
  }

  /// decay HF ratio The valid range is [100, 2000].
  static Future<int> getDecayHFRatio() async {
    return (await channel.invokeMethod("getDecayHFRatio"));
  }

  /// reflections getReflectionsLevel The valid range is [-9000, 1000]
  static void setReflectionsDelayLevel(int reflectionsLevel) async {
    await channel.invokeMethod(
        "setReflectionsLevel", {"reflectionsLevel": reflectionsLevel});
  }

  /// reflections getReflectionsLevel The valid range is [-9000, 1000]
  static Future<int> getReflectionsLevel() async {
    return (await channel.invokeMethod("getReflectionsLevel"));
  }

  /// initialize DSP engine
  static void _initDSPEngine(int audioSessionId) async {
    await channel.invokeMethod("initDSPEngine", {"dspId": audioSessionId});
  }

  static void enableDSPEngine(bool enable) async {
    await channel.invokeMethod("enableDSP", {"enableEngine": enable});
  }

  static void setOutGain(double limit) async {
    await channel.invokeMethod("setOutGain", {"outGain": limit});
  }

  static Future<double> getOutGain() async {
    return await channel.invokeMethod("getOutGain");
  }

  static Future<double> setDSPVolume(double v) async {
    return await channel.invokeMethod("setDSPVolume", {"dspVolume": v});
  }

  @Deprecated("shouldn't be used anymore")
  static void setChannelGain(double v) async {
    //  await channel.invokeMethod("setChannelGain", {"chGain": v});
  }
  @Deprecated("shouldn't be used anymore")
  static void setChannel2Gain(double v) async {
    //  await channel.invokeMethod("setChannel2Gain", {"ch2Gain": v});
  }
  static void enableTuner(bool enable) async {
    await channel.invokeMethod("enableTuner", {"enableTuner": enable});
  }

  static void setTunerBass(double value) async {
    await channel.invokeMethod("setTunerBass", {"tunerBass": value});
  }

  static void setDSPXBass(double bass) async {
    await channel.invokeMethod("setDSPXBass", {"xBass": bass});
  }

  static void setDSPXBass2(double gain2) async {
    log("XBass2 $gain2");
    await channel.invokeMethod("setExtraBass", {"extraBass": gain2});
  }

  static void setDSPPowerBass(double bass) async {
    await channel.invokeMethod("setDSPPowerBass", {"powerBass": bass});
  }

  static void setDSPTreble(double treble) async {
    await channel.invokeMethod("setDSPXTreble", {"trebleGain": treble});
  }

  static void setDSPSpeakers(
      List<dynamic> speakers, List<double> levels) async {
    Map<String, dynamic> dsps = {"speakers": speakers, "levels": levels};
    await channel.invokeMethod("setDSPSpeakers", {"spks": dsps});
  }

  static void disposeDSP() async {
    await channel.invokeMethod("disposeDSP");
  }

  static void _initPresetReverb(int sessionId) async {
    await channel.invokeMethod("initPresetReverb", {"priorityId": sessionId});
  }

  static Future<int> enablePresetReverb(bool enable) async {
    return await channel
        .invokeMethod("enablePresetReverb", {"enablePreset": enable});
  }

  static void setCutOffFreq(int freq) async {
    await channel.invokeMethod("setCutOffFreq", {"tunerBassFreq": freq});
  }

  static Future<double> getVocalLevel() async {
    return await channel.invokeMethod("getVocalLevel");
  }

  static void setReverbPreset(PresetReverb preset) async {
    int x = 0;
    switch (preset) {
      case PresetReverb.NONE:
        x = 0;
        break;

      case PresetReverb.SMALL_ROOM:
        x = 1;
        break;
      case PresetReverb.LARGE_ROOM:
        x = 3;
        break;
      case PresetReverb.PRESET_PLATE:
        x = 6;
        break;
      case PresetReverb.MEDIUM_ROOM:
        x = 2;
        break;
      case PresetReverb.MEDIUM_HALL:
        x = 4;
        break;
      case PresetReverb.LARGE_HALL:
        x = 5;
        break;
      case PresetReverb.PRESET:
        x = 0;
        break;
    }
    await channel.invokeMethod("setReverbPreset", {"preset": x});
  }

  static Future<int> getReverbPreset() async {
    return await channel.invokeMethod("getReverbPreset");
  }

  static void setSessionId(int sessionId) async {
    _initVirtualizer(sessionId);
    _initReverb(sessionId);
    _initDSPEngine(sessionId);
    _initPresetReverb(sessionId);
    await channel.invokeMethod("init", {"sessionId": sessionId});
  }
}
