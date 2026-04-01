// ignore_for_file: constant_identifier_names
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  // ==================== Global EQ (System-Wide) ====================

  /// Enable or disable global EQ (applies EQ to all apps).
  /// Returns true if the command was accepted, false if API < 28.
  static Future<bool> enableGlobalEq(bool enable) async {
    return await _invokeRequired<bool>("enableGlobalEq", false, {"enable": enable});
  }

  /// Check if global EQ is currently running.
  static Future<bool> isGlobalEqEnabled() async {
    return await _invokeRequired<bool>("isGlobalEqEnabled", false);
  }

  /// Check if global EQ is available on this device (API 28+).
  static Future<bool> isGlobalEqAvailable() async {
    return await _invokeRequired<bool>("isGlobalEqAvailable", false);
  }

  /// Returns list of {package, name} maps for apps currently playing audio.
  static Future<List<Map<String, String>>> getPlayingApps() async {
    final result = await _invoke<List<dynamic>>("getPlayingApps");
    if (result == null) return [];
    return result
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
  }

  /// Returns the PNG icon bytes for a given package name, or null if unavailable.
  static Future<Uint8List?> getAppIcon(String packageName) async {
    return await _invoke<Uint8List>("getAppIcon", {"package": packageName});
  }

  /// Check if battery optimization is disabled (app is unrestricted).
  static Future<bool> isBatteryOptimizationDisabled() async {
    return await _invokeRequired<bool>("isBatteryOptimizationDisabled", false);
  }

  /// Request the user to disable battery optimization for this app.
  static Future<bool> requestDisableBatteryOptimization() async {
    return await _invokeRequired<bool>("requestDisableBatteryOptimization", false);
  }

  // ==================== EQ Mode Notification ====================

  /// Start the EQ mode foreground service with persistent notification.
  static Future<bool> startEqModeService(String preset) async {
    return await _invokeRequired<bool>("startEqModeService", false, {"preset": preset});
  }

  /// Stop the EQ mode foreground service.
  static Future<bool> stopEqModeService() async {
    return await _invokeRequired<bool>("stopEqModeService", false);
  }

  /// Update the preset name shown in the EQ mode notification.
  static Future<bool> updateEqModePreset(String preset) async {
    return await _invokeRequired<bool>("updateEqModePreset", false, {"preset": preset});
  }

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

  // ==================== Tone Controls (Bass/Treble) ====================

  /// Enable/disable tone controls (independent bass/treble shelf filters)
  static Future<void> dspSetToneEnabled(bool enabled) async {
    await _invoke("dspSetToneEnabled", {"enabled": enabled});
  }

  /// Bass gain (-15 to +15 dB)
  static Future<void> dspSetBassGain(double dB) async {
    await _invoke("dspSetBassGain", {"value": dB});
  }

  /// Bass frequency (20 - 500 Hz, default 80)
  static Future<void> dspSetBassFreq(double hz) async {
    await _invoke("dspSetBassFreq", {"value": hz});
  }

  /// Bass Q (0.1 - 4.0, default 0.707)
  static Future<void> dspSetBassQ(double q) async {
    await _invoke("dspSetBassQ", {"value": q});
  }

  /// Treble gain (-15 to +15 dB)
  static Future<void> dspSetTrebleGain(double dB) async {
    await _invoke("dspSetTrebleGain", {"value": dB});
  }

  /// Treble frequency (1000 - 20000 Hz, default 10000)
  static Future<void> dspSetTrebleFreq(double hz) async {
    await _invoke("dspSetTrebleFreq", {"value": hz});
  }

  /// Treble Q (0.1 - 4.0, default 0.707)
  static Future<void> dspSetTrebleQ(double q) async {
    await _invoke("dspSetTrebleQ", {"value": q});
  }

  // ==================== Output Limiter ====================

  /// Enable/disable output limiter (on by default — safety net)
  static Future<void> dspSetLimiterEnabled(bool enabled) async {
    await _invoke("dspSetLimiterEnabled", {"enabled": enabled});
  }

  /// Limiter ceiling (0.01 - 1.0, default 0.98)
  static Future<void> dspSetLimiterCeiling(double value) async {
    await _invoke("dspSetLimiterCeiling", {"value": value});
  }

  /// Limiter release time in ms (10 - 500, default 50)
  static Future<void> dspSetLimiterRelease(double ms) async {
    await _invoke("dspSetLimiterRelease", {"value": ms});
  }

  /// Limiter soft knee width in dB (0 - 12, default 6)
  static Future<void> dspSetLimiterKnee(double dB) async {
    await _invoke("dspSetLimiterKnee", {"value": dB});
  }

  // ==================== Speaker Correction EQ (AutoEq) ====================

  static Future<void> setSpeakerEqEnabled(bool enabled) async {
    await _invoke("setSpeakerEqEnabled", {"enabled": enabled});
  }

  static Future<void> setSpeakerEqBands(List<Map<String, dynamic>> bands) async {
    final freqs = bands.map((b) => (b['fc'] as num).toDouble()).toList();
    final gains = bands.map((b) => (b['gain'] as num).toDouble()).toList();
    final qs = bands.map((b) => (b['q'] as num).toDouble()).toList();
    final types = bands.map((b) => (b['type'] as int)).toList();
    await _invoke("setSpeakerEqBands", {
      "freqs": freqs,
      "gains": gains,
      "qs": qs,
      "types": types,
    });
  }

  static Future<void> clearSpeakerEq() async {
    await _invoke("clearSpeakerEq");
  }

  // ----------- MBC Compressor (C++ pipeline) ------------------

  static void setDspNoiseThreshold(double noiseValue) async {
    await _invoke("setDspNoiseThreshold", {"noiseThreshold": noiseValue});
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

  static Future<void> setParametricBand(int band, double freq, double gain,
      {double q = 1.4, int filterType = 0, bool enabled = true}) async {
    await _invoke("setParametricBand", {
      "band": band, "freq": freq, "gain": gain,
      "q": q, "filterType": filterType, "enabled": enabled,
    });
  }

  static Future<void> setParametricAllBands(List<double> freqs, List<double> gains,
      {List<double>? qs}) async {
    await _invoke("setParametricAllBands", {
      "freqs": freqs, "gains": gains,
      if (qs != null) "qs": qs,
    });
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
    _initLoudnessEnhancer(sessionId);
    await _invoke("init", {"sessionId": sessionId});
  }

  // ==================== Audio Fingerprinting ====================

  /// Generates a Chromaprint fingerprint from an audio file.
  /// Returns {fingerprint: String, duration: int (seconds)} or null on failure.
  static Future<Map<String, dynamic>?> generateFingerprint(String filePath) async {
    final result = await _invoke<Map>("generateFingerprint", {
      "filePath": filePath,
    });
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  /// Writes metadata tags to an audio file (fill-empty policy).
  /// Supports MP3, M4A, FLAC, OGG, WMA via JAudioTagger.
  /// [artworkPath] optional local path to cover art image to embed.
  static Future<bool> writeTags(String filePath, Map<String, String> tags,
      {String? artworkPath}) async {
    return await _invokeRequired<bool>(
      "writeTags",
      false,
      {
        "filePath": filePath,
        "tags": tags,
        if (artworkPath != null) "artworkPath": artworkPath,
      },
    );
  }

  /// Triggers Android MediaStore re-scan for the given file path.
  /// Call after writing tags so queries return updated metadata.
  static Future<void> scanMediaFile(String filePath) async {
    await _invoke("scanMediaFile", {"filePath": filePath});
  }

  // ==================== Audio Metadata Extraction ====================

  /// Extracts metadata from any audio format via MediaMetadataRetriever.
  /// Works with HTTP URLs (for cloud files) using auth headers.
  /// Returns: {title, artist, album, durationMs, hasArtwork}
  static Future<Map<String, dynamic>?> extractAudioMetadata({
    required String url,
    Map<String, String> headers = const {},
    String? artworkPath,
  }) async {
    final result = await _invoke<Map>("extractAudioMetadata", {
      "url": url,
      "headers": headers,
      "artworkPath": artworkPath,
    });
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  // ==================== Stem Separation ====================

  static Future<bool> separateStems(String filePath, String outputDir) async {
    return await _invokeRequired<bool>("separateStems", false, {
      "filePath": filePath,
      "outputDir": outputDir,
    });
  }

  static Future<void> cancelStemSeparation() async {
    await _invoke("cancelStemSeparation");
  }

  static Future<bool> checkStemsExist(String dirPath) async {
    return await _invokeRequired<bool>("checkStemsExist", false, {
      "dirPath": dirPath,
    });
  }

  // ==================== Stem Mixer ====================

  static Future<bool> loadStems({
    required String vocalsPath,
    required String drumsPath,
    required String bassPath,
    required String otherPath,
  }) async {
    return await _invokeRequired<bool>("loadStems", false, {
      "vocals": vocalsPath,
      "drums": drumsPath,
      "bass": bassPath,
      "other": otherPath,
    });
  }

  static Future<void> unloadStems() async {
    await _invoke("unloadStems");
  }

  static Future<void> activateStemMode() async {
    await _invoke("activateStemMode");
  }

  static Future<void> deactivateStemMode() async {
    await _invoke("deactivateStemMode");
  }

  static Future<void> setStemVolume(int stem, double volume) async {
    await _invoke("setStemVolume", {"stem": stem, "volume": volume});
  }

  static Future<void> setStemMute(int stem, bool muted) async {
    await _invoke("setStemMute", {"stem": stem, "muted": muted});
  }

  static Future<void> setStemSolo(int stem, bool soloed) async {
    await _invoke("setStemSolo", {"stem": stem, "soloed": soloed});
  }

  static Future<void> stemSeek(int samplePosition) async {
    await _invoke("stemSeek", {"samplePosition": samplePosition});
  }

  static const EventChannel _stemProgressChannel =
      EventChannel("eq_app/stem_progress");

  static Stream<Map<String, dynamic>> get stemProgressStream =>
      _stemProgressChannel
          .receiveBroadcastStream()
          .map((event) => Map<String, dynamic>.from(event as Map));

  // ==================== Lyrics ====================

  /// Reads embedded lyrics from any audio format (MP3, M4A, FLAC, OGG, WMA).
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
