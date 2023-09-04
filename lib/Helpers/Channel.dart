import 'package:flutter/services.dart';

class Channel {
  static MethodChannel channel = const MethodChannel("eq_app");

  /// initializing Equalizer

  static void dispose() async {
    await channel.invokeMethod("release");
  }

  static Future<List<String>> getPreset() async {
    List<String> p =
        (await channel.invokeMethod("getPresetNames")).cast<String>();
    return p;
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

  static void setSessionId(int sessionId) async {
    initBassBoost(sessionId);
    initLoudnessEnhancer(sessionId);
    initVirtualizer(sessionId);
    initReverb(sessionId);
    await channel.invokeMethod("init", {"sessionId": sessionId});
  }

  /// initializing bass boost
  static void initBassBoost(int sessionId) async {
    await channel.invokeMethod("initBassBoost", {"sessionId": sessionId});
  }

  static void enableBass(bool enable) async {
    await channel.invokeMethod("enableBassBoost", {"enableBass": enable});
  }

  static Future<bool> isBassEnabled() async {
    return (await channel.invokeMethod("isBassEnabled"));
  }

  static Future<int> getBassStrength() async {
    return await channel.invokeMethod("bassBoostStrength");
  }

  static void setBassStrength(int strength) async {
    await channel.invokeMethod("setBassBoostStrength", {"strength": strength});
  }

  /// Virtualizer
  static void initVirtualizer(int sessionId) async {
    await channel.invokeMethod("initVirtualizer", {"sessionId": sessionId});
  }

  static void enableVirtualizer(bool enable) async {
    await channel.invokeMethod("enableVirtualizer", {"enable": enable});
  }

  static void setVirtualizerStrength(int strength) async {
    await channel
        .invokeMethod("setVirtualizerStrength", {"strength": strength});
  }

  static Future<int> getVirtualizerStrength() async {
    return (await channel.invokeMethod("virtualizerStrength"));
  }

  /// Loudness
  static void initLoudnessEnhancer(int sessionId) async {
    await channel
        .invokeMethod("initLoudnessEnhancer", {"sessionId": sessionId});
  }

  static void enableLoudnessEnhancer(bool enable) async {
    await channel
        .invokeMethod("enableLoudnessEnhancer", {"enableLoud": enable});
  }

  /// Sets the target gain
  static void setTargetGain(int strength) async {
    await channel
        .invokeMethod("setLoudnessEnhancerStrength", {"strength": strength});
  }

  /// retrieves the target gain value
  static Future<double> getTargetGain() async {
    return (await channel.invokeMethod("loudnessEnhancerStrength"));
  }

  // Reverb effects
  static void initReverb(int sessionId) async {
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
}
