import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:eq_app/Global/index.dart';
import '/exports/exports.dart';

import '../Helpers/AudioHandler.dart';
import '../Helpers/Channel.dart';
import '../Helpers/index.dart';
import '../models/eq_models.dart';
import '../models/room_preset.dart';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/cloud_file.dart';
import '../services/cloud_auth_service.dart';
import '../services/cloud_cache_service.dart';
import '../services/cloud_metadata_service.dart';
import '../services/google_drive_service.dart';
import '../services/dropbox_service.dart';
import '../services/lyrics_service.dart';
import '../services/fingerprint_service.dart';
import '../models/lyrics_model.dart';
import '../models/recognition_result.dart';
import '../models/speaker_profile.dart';
import 'stem_controller.dart';

class AppController with ChangeNotifier {
  static AppController? _instance;
  static AppController get instance => _instance!;

  // Cloud services
  late final CloudAuthService cloudAuth;
  late final CloudCacheService cloudCache;
  late final CloudMetadataService cloudMetadata;
  late final GoogleDriveService googleDriveService;
  late final DropboxService dropboxService;

  // Lyrics
  final LyricsService _lyricsService = LyricsService();
  LyricsService get lyricsService => _lyricsService;

  // Fingerprint / track recognition
  late final FingerprintService fingerprintService;
  LyricsData? _currentLyrics;
  LyricsData? get currentLyrics => _currentLyrics;
  bool _lyricsLoading = false;
  bool get lyricsLoading => _lyricsLoading;
  int? _lyricsLoadTarget; // songId index currently being loaded

  bool get isGoogleConnected => cloudAuth.isGoogleConnected;
  bool get isDropboxConnected => cloudAuth.isDropboxConnected;

  List<int> bandValues = [0, 0, 0, 0, 0];
  // app themes
  String _selectedTheme = "light";
  final bool _isDark = false;
  bool _playerVisual = false;

  bool _enableEffects = false;
  bool get enableEffects => _enableEffects;
  set enableEffects(bool value) {
    _prefs.setBool("enableEffects", value);
    _enableEffects = value;
    notifyListeners();
  }

  final HypeAudioHandler _handler;
  HypeAudioHandler get handler => _handler;
  int _selectedRoomPreset = -1;

  // MBC compressor settings (routed to C++ pipeline)
  double _dspNoise = -10.0;
  double _kneeWidth = 0.40;
  double _expandRatio = 15.0;
  double _preGain = 20;

  // Audio feature settings
  bool _gaplessPlayback = true;
  int _crossfadeDuration = 0; // seconds, 0 = off
  bool _replayGain = false;
  bool _dvcEnabled = false;
  double _dvcGain = -30.0; // dB, range -30 to 0 (0% to 100%)
  bool _dvcFineSteps = false; // false=1.5dB (5%), true=0.3dB (1%)

  // Global EQ (system-wide)
  bool _globalEqEnabled = false;
  bool _globalEqAvailable = false;
  List<Map<String, String>> _playingApps = [];

  // Song list/grid zoom: continuous extent (80=tiny grid, 300=list mode)
  double _songGridExtent = 300.0; // default list mode

  // Configurable EQ band count (UI-layer only, native always 32)
  int _eqBandCount = 32;

  // 32-band Graphic EQ state
  List<double> _graphicBandGains = List.filled(32, 0.0);
  bool _graphicEqEnabled = false;
  String _activePresetName = 'Flat';
  Map<String, EqPreset> _savedPresets = {};
  String _lastOutputDevice = 'speaker';
  bool _linkAllDevices = true;

  // Parametric EQ state
  List<ParametricPoint> _parametricPoints = [];

  // Preamp & MBC state
  double _preampGain = 0.0; // 0-15 dB
  bool _mbcEnabled = false;

  // Room effects state (custom DSP engine — float params 0.0-1.0)
  bool _reverbEnabled = false;
  double _dspRoomSize = 0.0;
  double _dspDecay = 0.0;
  double _dspDamping = 0.0;
  double _dspPreDelay = 0.0; // ms (0-200)
  double _dspDiffusion = 0.0;
  double _dspWetDry = 0.0;
  String _activeRoomPresetName = 'Off';

  // M/S stereo expander
  bool _stereoExpandEnabled = false;
  double _stereoWidth = 1.0; // 0.0=mono, 1.0=normal, 2.0=max

  // BS2B crossfeed
  bool _crossfeedEnabled = false;
  double _crossfeedCutoff = 700.0; // Hz (100-2000)
  double _crossfeedFeed = 4.5; // dB (1-15)

  // Tone controls (bass/treble shelf filters)
  bool _toneEnabled = false;
  double _bassGain = 0.0; // 0 to 20 dB
  double _bassFreq = 80.0; // 20-500 Hz
  double _bassQ = 0.707; // 0.1-4.0
  double _trebleGain = 0.0; // 0 to 20 dB
  double _trebleFreq = 10000.0; // 1000-20000 Hz
  double _trebleQ = 0.707; // 0.1-4.0

  // Output limiter (on by default)
  bool _limiterEnabled = true;

  // Speaker correction EQ (AutoEq headphone profiles)
  bool _speakerEqEnabled = false;
  String? _activeSpeakerProfile;
  final SpeakerProfileService _speakerProfileService = SpeakerProfileService();

  // Stem separation
  final StemController stemController = StemController();

  // Song grid extent getters/setters
  double get songGridExtent => _songGridExtent;
  set songGridExtent(double value) {
    final clamped = value.clamp(80.0, 300.0);
    if ((clamped - _songGridExtent).abs() > 0.5) {
      _songGridExtent = clamped;
      _prefs.setDouble("songGridExtent", clamped);
      notifyListeners();
    }
  }

  // EQ band count getters/setters
  int get eqBandCount => _eqBandCount;
  set eqBandCount(int value) {
    if (BandMapping.supportedCounts.contains(value)) {
      _prefs.setInt("eqBandCount", value);
      _eqBandCount = value;
      notifyListeners();
    }
  }

  BandMapping get currentBandMapping => BandMapping.forCount(_eqBandCount);

  List<double> get displayBandGains =>
      currentBandMapping.nativeToDisplay(_graphicBandGains);

  void setDisplayBandGain(int displayBand, double gain) {
    final mapping = currentBandMapping;
    if (displayBand >= 0 && displayBand < mapping.nativeGroups.length) {
      for (final nativeIdx in mapping.nativeGroups[displayBand]) {
        _graphicBandGains[nativeIdx] = gain;
      }
      Channel.setGraphicAllBands(_graphicBandGains);
      _persistGraphicGains();
      notifyListeners();
    }
  }

  // Graphic EQ getters/setters
  List<double> get graphicBandGains => _graphicBandGains;
  bool get graphicEqEnabled => _graphicEqEnabled;
  String get activePresetName => _activePresetName;
  Map<String, EqPreset> get savedPresets => _savedPresets;
  String get lastOutputDevice => _lastOutputDevice;
  bool get linkAllDevices => _linkAllDevices;
  List<ParametricPoint> get parametricPoints => _parametricPoints;
  double get preampGain => _preampGain;
  bool get mbcEnabled => _mbcEnabled;

  set preampGain(double value) {
    _preampGain = value.clamp(-15.0, 15.0);
    _prefs.setDouble("preampGain", _preampGain);
    Channel.setPreamp(_preampGain);
    notifyListeners();
  }

  // Tone controls getters/setters
  bool get toneEnabled => _toneEnabled;
  double get bassGain => _bassGain;
  double get bassFreq => _bassFreq;
  double get bassQ => _bassQ;
  double get trebleGain => _trebleGain;
  double get trebleFreq => _trebleFreq;
  double get trebleQ => _trebleQ;
  bool get limiterEnabled => _limiterEnabled;

  set toneEnabled(bool value) {
    _toneEnabled = value;
    _prefs.setBool("toneEnabled", value);
    Channel.dspSetToneEnabled(value);
    notifyListeners();
  }

  set bassGain(double value) {
    _bassGain = value.clamp(0.0, 30.0);
    _prefs.setDouble("bassGain", _bassGain);
    Channel.dspSetBassGain(_bassGain);
    notifyListeners();
  }

  set bassFreq(double value) {
    _bassFreq = value.clamp(20.0, 500.0);
    _prefs.setDouble("bassFreq", _bassFreq);
    Channel.dspSetBassFreq(_bassFreq);
    notifyListeners();
  }

  set bassQ(double value) {
    _bassQ = value.clamp(0.1, 4.0);
    _prefs.setDouble("bassQ", _bassQ);
    Channel.dspSetBassQ(_bassQ);
    notifyListeners();
  }

  set trebleGain(double value) {
    _trebleGain = value.clamp(0.0, 30.0);
    _prefs.setDouble("trebleGain", _trebleGain);
    Channel.dspSetTrebleGain(_trebleGain);
    notifyListeners();
  }

  set trebleFreq(double value) {
    _trebleFreq = value.clamp(1000.0, 20000.0);
    _prefs.setDouble("trebleFreq", _trebleFreq);
    Channel.dspSetTrebleFreq(_trebleFreq);
    notifyListeners();
  }

  set trebleQ(double value) {
    _trebleQ = value.clamp(0.1, 4.0);
    _prefs.setDouble("trebleQ", _trebleQ);
    Channel.dspSetTrebleQ(_trebleQ);
    notifyListeners();
  }

  set limiterEnabled(bool value) {
    _limiterEnabled = value;
    _prefs.setBool("limiterEnabled", value);
    Channel.dspSetLimiterEnabled(value);
    notifyListeners();
  }

  set mbcEnabled(bool value) {
    _mbcEnabled = value;
    _prefs.setBool("mbcEnabled", value);
    Channel.enableMbc(value);
    notifyListeners();
  }

  // Speaker correction EQ getters/setters
  bool get speakerEqEnabled => _speakerEqEnabled;
  String? get activeSpeakerProfile => _activeSpeakerProfile;
  List<SpeakerProfile> get speakerProfiles => _speakerProfileService.profiles;

  set speakerEqEnabled(bool value) {
    _speakerEqEnabled = value;
    _prefs.setBool("speakerEqEnabled", value);
    Channel.setSpeakerEqEnabled(value);
    notifyListeners();
  }

  Future<void> loadSpeakerProfiles() async {
    await _speakerProfileService.load();
  }

  Future<void> applySpeakerProfile(String name) async {
    final profile = _speakerProfileService.profiles
        .where((p) => p.name == name)
        .firstOrNull;
    if (profile == null) return;

    _activeSpeakerProfile = name;
    _speakerEqEnabled = true;
    _prefs.setString("activeSpeakerProfile", name);
    _prefs.setBool("speakerEqEnabled", true);

    final bands = profile.filters.map((f) => f.toNativeMap()).toList();
    await Channel.setSpeakerEqBands(bands);
    await Channel.setSpeakerEqEnabled(true);
    notifyListeners();
  }

  Future<void> clearSpeakerProfile() async {
    _activeSpeakerProfile = null;
    _speakerEqEnabled = false;
    _prefs.remove("activeSpeakerProfile");
    _prefs.setBool("speakerEqEnabled", false);
    await Channel.clearSpeakerEq();
    await Channel.setSpeakerEqEnabled(false);
    notifyListeners();
  }

  List<SpeakerProfile> searchSpeakerProfiles(String query) {
    return _speakerProfileService.search(query);
  }

  set graphicEqEnabled(bool value) {
    _prefs.setBool("graphicEqEnabled", value);
    _graphicEqEnabled = value;
    notifyListeners();
  }

  set activePresetName(String value) {
    _prefs.setString("activePresetName", value);
    _activePresetName = value;
    notifyListeners();
  }

  set linkAllDevices(bool value) {
    _prefs.setBool("linkAllDevices", value);
    _linkAllDevices = value;
    notifyListeners();
  }

  void setGraphicBandGain(int band, double gain) {
    if (band >= 0 && band < _graphicBandGains.length) {
      _graphicBandGains[band] = gain;
      Channel.setGraphicBandGain(band, gain);
      _persistGraphicGains();
      notifyListeners();
    }
  }

  void setGraphicAllBands(List<double> gains) {
    _graphicBandGains = List<double>.from(gains);
    Channel.setGraphicAllBands(gains);
    _persistGraphicGains();
    notifyListeners();
  }

  void applyBuiltInPreset(String name) {
    final gains = BuiltInPresets.presets[name];
    if (gains != null) {
      setGraphicAllBands(gains);
      activePresetName = name;
    }
  }

  void savePreset(String name) {
    _savedPresets[name] = EqPreset(
      name: name,
      graphicGains: List<double>.from(_graphicBandGains),
      parametric: _parametricPoints.map((p) => p.copyWith()).toList(),
      preamp: _preampGain,
      deviceType: _linkAllDevices ? null : _lastOutputDevice,
    );
    _prefs.setString("eqPresets", EqPreset.encodeList(_savedPresets));
    notifyListeners();
  }

  void loadPreset(String name) {
    final preset = _savedPresets[name];
    if (preset != null) {
      setGraphicAllBands(preset.graphicGains);
      _parametricPoints = preset.parametric.map((p) => p.copyWith()).toList();
      _applyParametricToNative();
      preampGain = preset.preamp;
      activePresetName = name;
    }
  }

  void deletePreset(String name) {
    _savedPresets.remove(name);
    _prefs.setString("eqPresets", EqPreset.encodeList(_savedPresets));
    notifyListeners();
  }

  // Parametric EQ methods
  void addParametricPoint(double frequency, double gain) {
    _parametricPoints.add(ParametricPoint(frequency: frequency, gain: gain));
    _applyParametricToNative();
    _persistParametricPoints();
    notifyListeners();
  }

  void updateParametricPoint(
    int index, {
    double? frequency,
    double? gain,
    double? q,
    bool? enabled,
  }) {
    if (index >= 0 && index < _parametricPoints.length) {
      _parametricPoints[index] = _parametricPoints[index].copyWith(
        frequency: frequency,
        gain: gain,
        q: q,
        enabled: enabled,
      );
      _applyParametricToNative();
      _persistParametricPoints();
      notifyListeners();
    }
  }

  void removeParametricPoint(int index) {
    if (index >= 0 && index < _parametricPoints.length) {
      _parametricPoints.removeAt(index);
      _applyParametricToNative();
      _persistParametricPoints();
      notifyListeners();
    }
  }

  void resetParametricPoints() {
    _parametricPoints.clear();
    _applyParametricToNative();
    _persistParametricPoints();
    notifyListeners();
  }

  void _applyParametricToNative() {
    // Map parametric points to 32 native bands
    final freqs = List.filled(32, 1000.0);
    final gains = List.filled(32, 0.0);
    final qs = List.filled(32, 1.4);
    for (int i = 0; i < _parametricPoints.length && i < 32; i++) {
      freqs[i] = _parametricPoints[i].frequency;
      gains[i] = _parametricPoints[i].enabled ? _parametricPoints[i].gain : 0.0;
      qs[i] = _parametricPoints[i].q;
    }
    Channel.setParametricAllBands(freqs, gains, qs: qs);
  }

  void _persistGraphicGains() {
    _prefs.setString("graphicBandGains", json.encode(_graphicBandGains));
  }

  void _persistParametricPoints() {
    _prefs.setString(
      "parametricPoints",
      json.encode(_parametricPoints.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> detectAndApplyDevicePreset() async {
    final device = await Channel.getAudioOutputType();
    if (device != _lastOutputDevice && !_linkAllDevices) {
      // Save current for old device
      _savedPresets['_device_$_lastOutputDevice'] = EqPreset(
        name: '_device_$_lastOutputDevice',
        graphicGains: List<double>.from(_graphicBandGains),
        parametric: _parametricPoints.map((p) => p.copyWith()).toList(),
        preamp: _preampGain,
        deviceType: _lastOutputDevice,
      );
      _prefs.setString("eqPresets", EqPreset.encodeList(_savedPresets));

      // Load preset for new device if it exists
      final devicePreset = _savedPresets['_device_$device'];
      if (devicePreset != null) {
        setGraphicAllBands(devicePreset.graphicGains);
        _parametricPoints = devicePreset.parametric
            .map((p) => p.copyWith())
            .toList();
        _applyParametricToNative();
        preampGain = devicePreset.preamp;
      }
    }
    _lastOutputDevice = device;
    _prefs.setString("lastOutputDevice", device);
    notifyListeners();
  }

  // Audio feature getters
  bool get gaplessPlayback => _gaplessPlayback;
  int get crossfadeDuration => _crossfadeDuration;
  bool get replayGain => _replayGain;
  bool get dvcEnabled => _dvcEnabled;
  double get dvcGain => _dvcGain;
  bool get dvcFineSteps => _dvcFineSteps;
  bool get globalEqEnabled => _globalEqEnabled;
  bool get globalEqAvailable => _globalEqAvailable;
  List<Map<String, String>> get playingApps => List.unmodifiable(_playingApps);

  // Audio feature setters
  set gaplessPlayback(bool value) {
    _prefs.setBool("gaplessPlayback", value);
    _gaplessPlayback = value;
    if (value && _crossfadeDuration > 0) {
      // Gapless and crossfade are mutually exclusive
      crossfadeDuration = 0;
    }
    notifyListeners();
  }

  set crossfadeDuration(int value) {
    _prefs.setInt("crossfadeDuration", value);
    _crossfadeDuration = value;
    if (value > 0 && _gaplessPlayback) {
      // Crossfade > 0 forces gapless OFF
      _gaplessPlayback = false;
      _prefs.setBool("gaplessPlayback", false);
    }
    notifyListeners();
  }

  set replayGain(bool value) {
    _prefs.setBool("replayGain", value);
    _replayGain = value;
    // Apply immediately if a song is loaded
    if (!value) {
      handler.player.setVolume(1.0);
    }
    notifyListeners();
  }

  set dvcEnabled(bool value) {
    _prefs.setBool("dvcEnabled", value);
    _dvcEnabled = value;
    if (value) {
      // Start at 0% (silence) so enabling DVC never blasts at full volume
      if (!_prefs.containsKey("dvcGain")) {
        _dvcGain = -30.0;
        _prefs.setDouble("dvcGain", _dvcGain);
      }
      Channel.enableDvc();
      Channel.setDvcGain(_dvcGain);
    } else {
      Channel.disableDvc();
    }
    notifyListeners();
  }

  set dvcGain(double value) {
    _prefs.setDouble("dvcGain", value);
    _dvcGain = value;
    Channel.setDvcGain(value);
    notifyListeners();
  }

  set dvcFineSteps(bool value) {
    _prefs.setBool("dvcFineSteps", value);
    _dvcFineSteps = value;
    notifyListeners();
  }

  set globalEqEnabled(bool value) {
    _prefs.setBool("globalEqEnabled", value);
    _globalEqEnabled = value;
    Channel.enableGlobalEq(value);
    if (value) {
      // Give the service a moment to start and detect sessions
      Future.delayed(const Duration(milliseconds: 800), refreshPlayingApps);
    } else {
      _playingApps = [];
    }
    notifyListeners();
  }

  Future<void> refreshPlayingApps() async {
    _playingApps = await Channel.getPlayingApps();
    notifyListeners();
  }

  // MBC compressor getters/setters
  double get dspNoise => _dspNoise;
  double get preGain => _preGain;
  double get kneeWidth => _kneeWidth;
  double get expandRatio => _expandRatio;

  set dspNoise(double noise) {
    _prefs.setDouble("dspNoise", noise);
    _dspNoise = noise;
    Channel.setDspNoiseThreshold(noise);
    notifyListeners();
  }

  set preGain(double gain) {
    _prefs.setDouble("preGain", gain);
    _preGain = gain;
    Channel.setPreGain(gain);
    notifyListeners();
  }

  set kneeWidth(double width) {
    _prefs.setDouble("kneeWidth", width);
    _kneeWidth = width;
    Channel.setDspKneeWidth(width);
    notifyListeners();
  }

  set expandRatio(double ratio) {
    _prefs.setDouble("expandRatio", ratio);
    _expandRatio = ratio;
    Channel.setDspExpandRatio(ratio);
    notifyListeners();
  }

  Widget _nowWidget = Container();
  Widget get nowWidget => _nowWidget;
  set nowWidget(Widget w) {
    _nowWidget = w;
    notifyListeners();
  }

  double _bgQuality = 2.0;
  int _selectedPreset = 0;
  bool _isFancy = false;
  bool _isShuffled = false;
  bool _isVisualInBackground = false;
  bool _visuals = false;

  // Visualizer fine-tuning
  String _visualizerStyle = 'circular';
  int _visualizerColor = 0xFFFFFFFF; // white
  int _visualizerFrameRate = 30;
  double _visualizerReactivity = 0.15; // smoothing attack factor

  // projectM MilkDrop settings
  int _milkdropFps = 30;
  double _milkdropBeatSensitivity = 1.0;
  double _milkdropPresetDuration = 30.0; // seconds, 0 = manual only
  bool _milkdropPresetLocked = false;
  String _milkdropPresetName = '';
  int _milkdropQuality = 1; // 0=Low, 1=Medium, 2=High, 3=Ultra
  int _songId = 0;
  int _artWorkId = 0;
  // Main method.
  final OnAudioQuery _audioQuery = OnAudioQuery();
  double _opacity = 0.0;
  double _blur = 40;

  final SharedPreferences _prefs;
  List<SongModel> _songs = [];
  List<SongModel> _shuffledSongs = [];

  StreamSubscription<Duration>? _positionSub;
  bool _isCrossfading = false;

  StreamSubscription<ProcessingState>? _processingSub;
  StreamSubscription<int?>? _indexSub;
  StreamSubscription<int?>? _sessionIdSub;
  StreamSubscription<String>? _dvcVolumeSub;

  // DVC volume overlay state
  bool _showDvcOverlay = false;
  Timer? _dvcOverlayTimer;

  bool get showDvcOverlay => _showDvcOverlay;

  /// DVC gain as 0–100 percentage (−30 dB = 0%, 0 dB = 100%).
  int get dvcVolumePercent =>
      ((_dvcGain + 30) / 30 * 100).round().clamp(0, 100);

  void _showDvcVolumeOverlay() {
    _showDvcOverlay = true;
    _dvcOverlayTimer?.cancel();
    _dvcOverlayTimer = Timer(const Duration(seconds: 2), () {
      _showDvcOverlay = false;
      notifyListeners();
    });
    notifyListeners();
  }

  AppController(this._prefs, this._handler) {
    _loadSettings();

    // Wire up notification skip controls
    _handler.onSkipToNext = next;
    _handler.onSkipToPrevious = prev;

    // When crossfade starts, notify UI so waveform binds to the new track player
    _handler.onCrossfadeStarted = () => notifyListeners();

    // Re-bind all player streams after a crossfade player swap
    _handler.onPlayerSwapped = _rebindPlayerStreams;

    // Apply DVC state on startup
    if (_dvcEnabled) {
      Channel.enableDvc();
      Channel.setDvcGain(_dvcGain);
    }

    // Global EQ: check availability and restore state
    _initGlobalEq();

    _bindDvcVolumeButtons();
    _bindProcessingState();
    _bindCurrentIndex();
    _setupCrossfadeListener();
    _bindAudioSessionId();

    // Fingerprint service
    fingerprintService = FingerprintService(_prefs);

    // Cloud services
    _instance = this;
    cloudAuth = CloudAuthService();
    cloudCache = CloudCacheService(_prefs);
    googleDriveService = GoogleDriveService(cloudAuth);
    dropboxService = DropboxService(cloudAuth);
    cloudMetadata = CloudMetadataService(
      cloudAuth,
      cloudCache,
      googleDriveService,
      dropboxService,
    );
    _initCloudServices();
  }

  /// Listen to audio session ID changes and rebind session-bound native effects.
  /// EQ, MBC, and room effects are NOT session-bound (C++ pipeline), only
  /// LoudnessEnhancer (DVC) needs rebinding.
  void _bindAudioSessionId() {
    _sessionIdSub?.cancel();
    _sessionIdSub = _handler.player.androidAudioSessionIdStream.listen((
      sessionId,
    ) {
      if (sessionId != null) {
        Channel.setSessionId(sessionId);
        // Re-apply DVC state after session change (LoudnessEnhancer is session-bound)
        if (_dvcEnabled) {
          Channel.enableDvc();
          Channel.setDvcGain(_dvcGain);
        }
      }
    });
  }

  /// Listen to hardware volume button events forwarded by DvcController.
  /// Android-only: iOS has no volume button interception API.
  void _bindDvcVolumeButtons() {
    if (!Platform.isAndroid) return;
    _dvcVolumeSub?.cancel();
    _dvcVolumeSub = Channel.dvcVolumeButtonStream.listen((direction) {
      if (!_dvcEnabled) return;
      final step = _dvcFineSteps ? 0.3 : 1.5;
      if (direction == "up") {
        dvcGain = (_dvcGain + step).clamp(-30.0, 0.0);
      } else if (direction == "down") {
        dvcGain = (_dvcGain - step).clamp(-30.0, 0.0);
      }
      _showDvcVolumeOverlay();
    });
  }

  /// Subscribe to the active player's processingStateStream.
  /// Called once at init and again after every crossfade swap.
  void _bindProcessingState() {
    _processingSub?.cancel();
    _processingSub = handler.player.processingStateStream.listen((event) {
      if (event == ProcessingState.ready) {
        preCacheNextCloudTracks();
        // On iOS, the MTAudioProcessingTap calls dsp_reinit() when a new
        // AVPlayerItem starts, resetting all DSP filters to defaults.
        // Re-apply all EQ/reverb/tone settings to the native engine.
        if (Platform.isIOS) {
          _applyAllDspParams();
        }
      }
      if (event == ProcessingState.completed) {
        if (_gaplessPlayback && handler.player.audioSources.length > 1) {
          final idx = handler.player.currentIndex ?? 0;
          if (idx >= songs.length - 1) {
            handler.player.stop();
          }
        } else if (!_isCrossfading) {
          if (songId >= songs.length - 1) {
            handler.player.stop();
          } else {
            songId += 1;
            artWorkId = songs[songId].id;
            loadAudioSource(handler, songs[songId], replayGain: _replayGain);
          }
        }
      }
    });
  }

  /// Subscribe to currentIndexStream for gapless mode index tracking.
  /// Only updates songId when the player actually has a multi-source queue
  /// loaded (audioSources.length > 1). When a single source is loaded via
  /// loadAudioSource(), the player always emits index 0 which would
  /// incorrectly overwrite the real songId.
  void _bindCurrentIndex() {
    _indexSub?.cancel();
    _indexSub = handler.player.currentIndexStream.listen((index) {
      if (index != null &&
          _gaplessPlayback &&
          songs.isNotEmpty &&
          index < songs.length &&
          handler.player.audioSources.length > 1) {
        _songId = index;
        _artWorkId = songs[index].id;
        _updateMediaItemForIndex(index);
        notifyListeners();
        _loadLyricsForCurrentSong();
      }
    });
  }

  /// Called by HypeAudioHandler after crossfade completes and players are swapped.
  /// Re-binds all subscriptions to the new active player and notifies the UI
  /// so StreamBuilders (waveform, playing state) reconnect to the new player.
  void _rebindPlayerStreams() {
    _bindProcessingState();
    _bindCurrentIndex();
    _setupCrossfadeListener();
    _bindAudioSessionId();
    // After crossfade swap, the new player's tap has reinited the DSP engine
    if (Platform.isIOS) {
      _applyAllDspParams();
    }
    notifyListeners();
  }

  void _setupCrossfadeListener() {
    _positionSub?.cancel();
    _positionSub = handler.player.positionStream.listen((position) {
      final duration = handler.player.duration;
      if (_crossfadeDuration > 0 &&
          !_isCrossfading &&
          duration != null &&
          duration.inSeconds > _crossfadeDuration &&
          position >= duration - Duration(seconds: _crossfadeDuration) &&
          songId < songs.length - 1) {
        _beginCrossfade();
      }
    });
  }

  Future<void> _beginCrossfade() async {
    if (_isCrossfading) return;
    _isCrossfading = true;
    final nextIdx = songId + 1;
    final nextSong = songs[nextIdx];

    _songId = nextIdx;
    _artWorkId = nextSong.id;
    _loadLyricsForCurrentSong();

    final AudioSource nextSource;
    if (nextSong.data.startsWith('http')) {
      if (nextSong.data.contains('nowviba.com')) {
        // Discover stream — direct URI, no proxy overhead
        nextSource = AudioSource.uri(Uri.parse(nextSong.data));
      } else {
        final fileId = nextSong.id.toString();
        if (cloudCache.isCached(fileId)) {
          nextSource = AudioSource.file(cloudCache.cacheFile(fileId).path);
        } else {
          final headers = nextSong.data.contains('googleapis.com')
              ? await cloudAuth.getGoogleAuthHeaders()
              : <String, String>{};
          nextSource = LockCachingAudioSource(
            Uri.parse(nextSong.data),
            cacheFile: cloudCache.cacheFile(fileId),
            headers: headers,
          );
        }
      }
    } else {
      nextSource = nextSong.data.startsWith('/')
          ? AudioSource.file(nextSong.data)
          : AudioSource.uri(Uri.parse(nextSong.data));
    }

    await handler.beginCrossfade(
      nextSource,
      nextSong,
      Duration(seconds: _crossfadeDuration),
      replayGain: _replayGain,
    );
    _isCrossfading = false;
  }

  Future<void> _updateMediaItemForIndex(int index) async {
    if (index >= songs.length) return;
    final song = songs[index];
    Uri? artUri;
    if (song.data.startsWith('http') &&
        song.album != null &&
        song.album!.startsWith('http')) {
      final downloaded = await _downloadCloudArtwork(song.album!, song.id);
      artUri = downloaded != null ? Uri.file(downloaded) : null;
    } else {
      final image = await fetchArtworkUrl(song.data, song.id);
      artUri = Uri.file(image);
    }
    handler.setCurrentMediaItem(
      MediaItem(
        id: song.data,
        album: song.album,
        title: song.title,
        artist: song.artist,
        duration: Duration(milliseconds: song.duration ?? 0),
        artUri: artUri,
      ),
    );
  }

  Future<String?> _downloadCloudArtwork(String url, int songId) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/cloud_art_$songId.png');
      if (file.existsSync()) return file.path;
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return file.path;
      }
    } catch (_) {}
    return null;
  }

  /// Central method for playing a song selected from any list.
  /// Properly handles gapless queue vs single-source loading.
  void playSongFromList(List<SongModel> songList, int index) {
    songs = songList;
    songId = index;
    artWorkId = songList[index].id;
    if (_gaplessPlayback && _crossfadeDuration == 0) {
      loadGaplessQueue(index);
    } else {
      loadAudioSource(handler, songList[index], replayGain: _replayGain);
    }
  }

  /// Build and load a queue for gapless playback.
  /// Cached cloud tracks play from disk; uncached ones stream with auth headers.
  bool _loadingQueue = false;
  Future<void> loadGaplessQueue(int startIndex) async {
    if (songs.isEmpty) return;
    // If already loading, the new call will interrupt the old one in just_audio.
    // That's fine — just_audio handles cancellation gracefully.
    _loadingQueue = true;
    final sources = <AudioSource>[];

    // Get auth headers once (reused for all cloud tracks of same provider)
    Map<String, String>? gdriveHeaders;
    Map<String, String>? dropboxHeaders;

    for (int i = 0; i < songs.length; i++) {
      final s = songs[i];
      if (s.data.startsWith('http')) {
        // Discover streams (nowviba.com) — direct URI, no proxy/cache overhead
        if (s.data.contains('nowviba.com')) {
          sources.add(AudioSource.uri(Uri.parse(s.data)));
        } else {
          final fileId = s.id.toString();
          if (cloudCache.isCached(fileId)) {
            sources.add(AudioSource.file(cloudCache.cacheFile(fileId).path));
          } else {
            Map<String, String> headers;
            if (s.data.contains('googleapis.com')) {
              gdriveHeaders ??= await cloudAuth.getGoogleAuthHeaders();
              headers = gdriveHeaders;
            } else {
              dropboxHeaders ??= <String, String>{};
              headers = dropboxHeaders;
            }
            sources.add(
              LockCachingAudioSource(
                Uri.parse(s.data),
                cacheFile: cloudCache.cacheFile(fileId),
                headers: headers,
              ),
            );
          }
        }
      } else {
        // Local file paths start with "/", use AudioSource.file to handle spaces/special chars
        if (s.data.startsWith('/')) {
          sources.add(AudioSource.file(s.data));
        } else {
          sources.add(AudioSource.uri(Uri.parse(s.data)));
        }
      }
    }
    try {
      await handler.player.setAudioSources(sources, initialIndex: startIndex);
      await _updateMediaItemForIndex(startIndex);
      handler.player.play();
    } catch (e) {
      // "Loading interrupted" — a newer load replaced this one; safe to ignore
      debugPrint('Gapless queue load: $e');
    } finally {
      _loadingQueue = false;
    }
  }

  void _loadSettings() {
    _enableEffects = _prefs.getBool("enableEffects") ?? false;
    _selectedPreset = _prefs.getInt("selectedPreset") ?? 0;
    _isFancy = _prefs.getBool("fancyMode") ?? false;
    _isShuffled = _prefs.getBool("isShuffled") ?? false;
    _isVisualInBackground = _prefs.getBool("isVisualInBackground") ?? false;
    _visuals = _prefs.getBool("visuals") ?? false;
    _bgQuality = _prefs.getDouble("bgQuality") ?? 2.0;
    _blur = _prefs.getDouble("blur") ?? 40.0;
    _selectedRoomPreset = _prefs.getInt("selectedRoomPreset") ?? 0;
    // MBC compressor
    _dspNoise = _prefs.getDouble("dspNoise") ?? 0.0;
    _expandRatio = _prefs.getDouble("expandRatio") ?? 15.0;
    _preGain = _prefs.getDouble("preGain") ?? 20.0;
    _kneeWidth = _prefs.getDouble("kneeWidth") ?? 0.4;
    // Audio features
    _gaplessPlayback = _prefs.getBool("gaplessPlayback") ?? true;
    _crossfadeDuration = _prefs.getInt("crossfadeDuration") ?? 0;
    _replayGain = _prefs.getBool("replayGain") ?? false;
    _dvcEnabled = _prefs.getBool("dvcEnabled") ?? false;
    _dvcGain = _prefs.getDouble("dvcGain") ?? -30.0;
    _dvcFineSteps = _prefs.getBool("dvcFineSteps") ?? false;
    _globalEqEnabled = _prefs.getBool("globalEqEnabled") ?? false;
    // Song grid extent (migrate from old int scale if needed)
    if (_prefs.containsKey("songGridExtent")) {
      _songGridExtent = (_prefs.getDouble("songGridExtent") ?? 300.0).clamp(80.0, 300.0);
    } else {
      // Migrate from old songGridScale: 0=list→300, 1=2-col→180, 2=3-col→120
      final oldScale = _prefs.getInt("songGridScale") ?? 0;
      _songGridExtent = oldScale == 0 ? 300.0 : oldScale == 1 ? 180.0 : 120.0;
    }
    // EQ band count
    _eqBandCount = _prefs.getInt("eqBandCount") ?? 32;
    // Preamp & MBC
    _preampGain = _prefs.getDouble("preampGain") ?? 0.0;
    _mbcEnabled = _prefs.getBool("mbcEnabled") ?? false;
    // Speaker correction EQ
    _speakerEqEnabled = _prefs.getBool("speakerEqEnabled") ?? false;
    _activeSpeakerProfile = _prefs.getString("activeSpeakerProfile");
    // 32-band Graphic EQ
    _graphicEqEnabled = _prefs.getBool("graphicEqEnabled") ?? false;
    _activePresetName = _prefs.getString("activePresetName") ?? 'Flat';
    _linkAllDevices = _prefs.getBool("linkAllDevices") ?? true;
    _lastOutputDevice = _prefs.getString("lastOutputDevice") ?? 'speaker';
    final graphicJson = _prefs.getString("graphicBandGains");
    if (graphicJson != null) {
      try {
        _graphicBandGains = (json.decode(graphicJson) as List)
            .map((e) => (e as num).toDouble())
            .toList();
      } catch (_) {}
    }
    final parametricJson = _prefs.getString("parametricPoints");
    if (parametricJson != null) {
      try {
        _parametricPoints = (json.decode(parametricJson) as List)
            .map((e) => ParametricPoint.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    final presetsJson = _prefs.getString("eqPresets");
    if (presetsJson != null) {
      try {
        _savedPresets = EqPreset.decodeList(presetsJson);
      } catch (_) {}
    }
    // Visualizer fine-tuning
    _visualizerStyle = _prefs.getString("visualizerStyle") ?? 'circular';
    _visualizerColor = _prefs.getInt("visualizerColor") ?? 0xFFFFFFFF;
    _visualizerFrameRate = _prefs.getInt("visualizerFrameRate") ?? 30;
    _visualizerReactivity = _prefs.getDouble("visualizerReactivity") ?? 0.15;

    // projectM MilkDrop settings
    _milkdropFps = _prefs.getInt("milkdropFps") ?? 30;
    _milkdropBeatSensitivity =
        _prefs.getDouble("milkdropBeatSensitivity") ?? 1.0;
    _milkdropPresetDuration =
        _prefs.getDouble("milkdropPresetDuration") ?? 30.0;
    _milkdropPresetLocked = _prefs.getBool("milkdropPresetLocked") ?? false;
    _milkdropPresetName = _prefs.getString("milkdropPresetName") ?? '';
    _milkdropQuality = _prefs.getInt("milkdropQuality") ?? 1;
    // Room effects (custom DSP)
    _reverbEnabled = _prefs.getBool("reverbEnabled") ?? false;
    _dspRoomSize = _prefs.getDouble("dspRoomSize") ?? 0.0;
    _dspDecay = _prefs.getDouble("dspDecay") ?? 0.0;
    _dspDamping = _prefs.getDouble("dspDamping") ?? 0.0;
    _dspPreDelay = _prefs.getDouble("dspPreDelay") ?? 0.0;
    _dspDiffusion = _prefs.getDouble("dspDiffusion") ?? 0.0;
    _dspWetDry = _prefs.getDouble("dspWetDry") ?? 0.0;
    _activeRoomPresetName = _prefs.getString("activeRoomPresetName") ?? 'Off';
    _stereoExpandEnabled = _prefs.getBool("stereoExpandEnabled") ?? false;
    _stereoWidth = _prefs.getDouble("dspStereoWidth") ?? 1.0;
    _crossfeedEnabled = _prefs.getBool("crossfeedEnabled") ?? false;
    _crossfeedCutoff = _prefs.getDouble("crossfeedCutoff") ?? 700.0;
    _crossfeedFeed = _prefs.getDouble("crossfeedFeed") ?? 4.5;
    // Tone controls
    _toneEnabled = _prefs.getBool("toneEnabled") ?? false;
    _bassGain = _prefs.getDouble("bassGain") ?? 0.0;
    _bassFreq = _prefs.getDouble("bassFreq") ?? 80.0;
    _bassQ = _prefs.getDouble("bassQ") ?? 0.707;
    _trebleGain = _prefs.getDouble("trebleGain") ?? 0.0;
    _trebleFreq = _prefs.getDouble("trebleFreq") ?? 10000.0;
    _trebleQ = _prefs.getDouble("trebleQ") ?? 0.707;
    // Output limiter
    _limiterEnabled = _prefs.getBool("limiterEnabled") ?? true;
    // Load speaker profiles from asset, then apply DSP params
    loadSpeakerProfiles().then((_) => _applyAllDspParams());
  }

  bool get isDark {
    return _isDark;
  }

  bool get isShuffled => _isShuffled;

  int get selectedPreset {
    return _selectedPreset;
  }

  bool get playerVisual => _playerVisual;
  double get bgQuality => _bgQuality;
  bool get isFancy {
    return _isFancy;
  }

  String get selectedTheme {
    return _selectedTheme;
  }

  bool get isVisualInBackground => _isVisualInBackground;
  set isVisualInBackground(bool b) {
    _prefs.setBool("isVisualInBackground", b);
    _isVisualInBackground = b;
    notifyListeners();
  }

  // Visualizer fine-tuning getters
  String get visualizerStyle => _visualizerStyle;
  int get visualizerColor => _visualizerColor;
  int get visualizerFrameRate => _visualizerFrameRate;
  double get visualizerReactivity => _visualizerReactivity;

  // Visualizer fine-tuning setters
  set visualizerStyle(String v) {
    _prefs.setString("visualizerStyle", v);
    _visualizerStyle = v;
    notifyListeners();
  }

  set visualizerColor(int c) {
    _prefs.setInt("visualizerColor", c);
    _visualizerColor = c;
    notifyListeners();
  }

  set visualizerFrameRate(int fps) {
    _prefs.setInt("visualizerFrameRate", fps);
    _visualizerFrameRate = fps;
    notifyListeners();
  }

  set visualizerReactivity(double r) {
    _prefs.setDouble("visualizerReactivity", r);
    _visualizerReactivity = r;
    notifyListeners();
  }

  // projectM MilkDrop getters/setters
  int get milkdropFps => _milkdropFps;
  set milkdropFps(int v) {
    _prefs.setInt("milkdropFps", v);
    _milkdropFps = v;
    notifyListeners();
  }

  double get milkdropBeatSensitivity => _milkdropBeatSensitivity;
  set milkdropBeatSensitivity(double v) {
    _prefs.setDouble("milkdropBeatSensitivity", v);
    _milkdropBeatSensitivity = v;
    notifyListeners();
  }

  double get milkdropPresetDuration => _milkdropPresetDuration;
  set milkdropPresetDuration(double v) {
    _prefs.setDouble("milkdropPresetDuration", v);
    _milkdropPresetDuration = v;
    notifyListeners();
  }

  bool get milkdropPresetLocked => _milkdropPresetLocked;
  set milkdropPresetLocked(bool v) {
    _prefs.setBool("milkdropPresetLocked", v);
    _milkdropPresetLocked = v;
    notifyListeners();
  }

  String get milkdropPresetName => _milkdropPresetName;
  set milkdropPresetName(String v) {
    _prefs.setString("milkdropPresetName", v);
    _milkdropPresetName = v;
  }

  int get milkdropQuality => _milkdropQuality;
  set milkdropQuality(int v) {
    _prefs.setInt("milkdropQuality", v);
    _milkdropQuality = v;
    notifyListeners();
  }

  int get songId {
    return _songId;
  }

  int get selectedRoomPreset => _selectedRoomPreset;
  set selectedRoomPreset(int x) {
    _prefs.setInt("selectedRoomPreset", x);
    _selectedRoomPreset = x;
    notifyListeners();
  }

  // ==================== Custom DSP Room Effects Getters/Setters ====================

  bool get reverbEnabled => _reverbEnabled;
  set reverbEnabled(bool v) {
    _prefs.setBool("reverbEnabled", v);
    final wasOff = !_reverbEnabled;
    _reverbEnabled = v;
    Channel.dspSetReverbEnabled(v);

    // When turning on for the first time (or from Off), reset to zeros
    // so the user starts with a clean slate before picking a preset.
    if (v && wasOff && _activeRoomPresetName == 'Off') {
      _dspRoomSize = 0.0;
      _dspDecay = 0.0;
      _dspDamping = 0.0;
      _dspPreDelay = 0.0;
      _dspDiffusion = 0.0;
      _dspWetDry = 0.0;
      Channel.dspSetRoomSize(0.0);
      Channel.dspSetDecay(0.0);
      Channel.dspSetDamping(0.0);
      Channel.dspSetPreDelay(0.0);
      Channel.dspSetDiffusion(0.0);
      Channel.dspSetReverbWetDry(0.0);
    }
    notifyListeners();
  }

  double get dspRoomSize => _dspRoomSize;
  set dspRoomSize(double v) {
    _prefs.setDouble("dspRoomSize", v);
    _dspRoomSize = v;
    Channel.dspSetRoomSize(v);
    notifyListeners();
  }

  double get dspDecay => _dspDecay;
  set dspDecay(double v) {
    _prefs.setDouble("dspDecay", v);
    _dspDecay = v;
    Channel.dspSetDecay(v);
    notifyListeners();
  }

  double get dspDamping => _dspDamping;
  set dspDamping(double v) {
    _prefs.setDouble("dspDamping", v);
    _dspDamping = v;
    Channel.dspSetDamping(v);
    notifyListeners();
  }

  double get dspPreDelay => _dspPreDelay;
  set dspPreDelay(double v) {
    _prefs.setDouble("dspPreDelay", v);
    _dspPreDelay = v;
    Channel.dspSetPreDelay(v);
    notifyListeners();
  }

  double get dspDiffusion => _dspDiffusion;
  set dspDiffusion(double v) {
    _prefs.setDouble("dspDiffusion", v);
    _dspDiffusion = v;
    Channel.dspSetDiffusion(v);
    notifyListeners();
  }

  double get dspWetDry => _dspWetDry;
  set dspWetDry(double v) {
    _prefs.setDouble("dspWetDry", v);
    _dspWetDry = v;
    Channel.dspSetReverbWetDry(v);
    notifyListeners();
  }

  String get activeRoomPresetName => _activeRoomPresetName;
  set activeRoomPresetName(String v) {
    _prefs.setString("activeRoomPresetName", v);
    _activeRoomPresetName = v;
    notifyListeners();
  }

  bool get stereoExpandEnabled => _stereoExpandEnabled;
  set stereoExpandEnabled(bool v) {
    _prefs.setBool("stereoExpandEnabled", v);
    _stereoExpandEnabled = v;
    Channel.dspSetStereoExpandEnabled(v);
    if (v && _crossfeedEnabled) {
      // Mutually exclusive — disable crossfeed
      _crossfeedEnabled = false;
      _prefs.setBool("crossfeedEnabled", false);
      Channel.dspSetCrossfeedEnabled(false);
    }
    notifyListeners();
  }

  double get stereoWidth => _stereoWidth;
  set stereoWidth(double v) {
    _prefs.setDouble("dspStereoWidth", v);
    _stereoWidth = v;
    Channel.dspSetStereoWidth(v);
    notifyListeners();
  }

  bool get crossfeedEnabled => _crossfeedEnabled;
  set crossfeedEnabled(bool v) {
    _prefs.setBool("crossfeedEnabled", v);
    _crossfeedEnabled = v;
    Channel.dspSetCrossfeedEnabled(v);
    if (v && _stereoExpandEnabled) {
      // Mutually exclusive — disable stereo expand
      _stereoExpandEnabled = false;
      _prefs.setBool("stereoExpandEnabled", false);
      Channel.dspSetStereoExpandEnabled(false);
    }
    notifyListeners();
  }

  double get crossfeedCutoff => _crossfeedCutoff;
  set crossfeedCutoff(double v) {
    _prefs.setDouble("crossfeedCutoff", v);
    _crossfeedCutoff = v;
    Channel.dspSetCrossfeedParams(_crossfeedCutoff, _crossfeedFeed);
    notifyListeners();
  }

  double get crossfeedFeed => _crossfeedFeed;
  set crossfeedFeed(double v) {
    _prefs.setDouble("crossfeedFeed", v);
    _crossfeedFeed = v;
    Channel.dspSetCrossfeedParams(_crossfeedCutoff, _crossfeedFeed);
    notifyListeners();
  }

  /// Check global EQ availability and restore state if previously enabled.
  Future<void> _initGlobalEq() async {
    _globalEqAvailable = await Channel.isGlobalEqAvailable();
    if (_globalEqAvailable && _globalEqEnabled) {
      Channel.enableGlobalEq(true);
    }
  }

  /// Applies all DSP params to the native C++ engine on startup.
  void _applyAllDspParams() {
    // Speaker correction EQ (restore profile if was active)
    if (_speakerEqEnabled && _activeSpeakerProfile != null) {
      applySpeakerProfile(_activeSpeakerProfile!);
    }
    // EQ
    Channel.enableEq(_graphicEqEnabled);
    Channel.setPreamp(_preampGain);
    Channel.setGraphicAllBands(_graphicBandGains);
    _applyParametricToNative();
    // MBC
    Channel.enableMbc(_mbcEnabled);
    Channel.setDspNoiseThreshold(_dspNoise);
    Channel.setDspKneeWidth(_kneeWidth);
    Channel.setDspExpandRatio(_expandRatio);
    Channel.setPreGain(_preGain);
    // Room effects
    Channel.dspSetReverbEnabled(_reverbEnabled);
    Channel.dspSetRoomSize(_dspRoomSize);
    Channel.dspSetDecay(_dspDecay);
    Channel.dspSetDamping(_dspDamping);
    Channel.dspSetPreDelay(_dspPreDelay);
    Channel.dspSetDiffusion(_dspDiffusion);
    Channel.dspSetReverbWetDry(_dspWetDry);
    Channel.dspSetStereoExpandEnabled(_stereoExpandEnabled);
    Channel.dspSetStereoWidth(_stereoWidth);
    Channel.dspSetCrossfeedEnabled(_crossfeedEnabled);
    Channel.dspSetCrossfeedParams(_crossfeedCutoff, _crossfeedFeed);
    // Tone controls
    Channel.dspSetToneEnabled(_toneEnabled);
    Channel.dspSetBassGain(_bassGain);
    Channel.dspSetBassFreq(_bassFreq);
    Channel.dspSetBassQ(_bassQ);
    Channel.dspSetTrebleGain(_trebleGain);
    Channel.dspSetTrebleFreq(_trebleFreq);
    Channel.dspSetTrebleQ(_trebleQ);
    // Output limiter
    Channel.dspSetLimiterEnabled(_limiterEnabled);
  }

  /// Applies a room preset, updating all parameters at once.
  void applyRoomPreset(RoomPreset preset) {
    _dspRoomSize = preset.roomSize;
    _dspDecay = preset.decay;
    _dspDamping = preset.damping;
    _dspPreDelay = preset.preDelay;
    _dspDiffusion = preset.diffusion;
    _dspWetDry = preset.wetDry;
    _activeRoomPresetName = preset.name;
    // Persist all
    _prefs.setDouble("dspRoomSize", _dspRoomSize);
    _prefs.setDouble("dspDecay", _dspDecay);
    _prefs.setDouble("dspDamping", _dspDamping);
    _prefs.setDouble("dspPreDelay", _dspPreDelay);
    _prefs.setDouble("dspDiffusion", _dspDiffusion);
    _prefs.setDouble("dspWetDry", _dspWetDry);
    _prefs.setString("activeRoomPresetName", _activeRoomPresetName);
    // Apply to native DSP
    Channel.dspSetRoomSize(_dspRoomSize);
    Channel.dspSetDecay(_dspDecay);
    Channel.dspSetDamping(_dspDamping);
    Channel.dspSetPreDelay(_dspPreDelay);
    Channel.dspSetDiffusion(_dspDiffusion);
    Channel.dspSetReverbWetDry(_dspWetDry);
    notifyListeners();
  }

  bool get visuals => _visuals;
  double get opacity => _opacity;
  double get blur => _blur;
  int get artWorkId => _artWorkId;
  List<SongModel> get songs {
    return isShuffled ? _shuffledSongs : _songs;
  }

  List<SongModel> get shuffledSongs => _shuffledSongs;

  OnAudioQuery get audioQuery => _audioQuery;

  set visuals(bool v) {
    _prefs.setBool("visuals", v);
    _visuals = v;
    notifyListeners();
  }

  set isShuffled(bool sh) {
    _prefs.setBool("isShuffled", sh);
    _isShuffled = sh;
    notifyListeners();
  }

  set selectedTheme(String t) {
    _prefs.setString("selectedTheme", t);
    _selectedTheme = t;
    notifyListeners();
  }

  // ========================
  set selectedPreset(int pr) {
    _prefs.setInt("selectedPreset", pr);
    _selectedPreset = pr;
    notifyListeners();
  }

  set playerVisual(bool pV) {
    _playerVisual = pV;
    notifyListeners();
  }

  /// adjusting player's background
  set bgQuality(double q) {
    _prefs.setDouble("bgQuality", q);
    _bgQuality = q;
    notifyListeners();
  }

  set isFancy(bool fancy) {
    _prefs.setBool("fancyMode", fancy);
    _isFancy = fancy;
    notifyListeners();
  }

  set songs(List<SongModel> value) {
    _songs = List.from(value);
    _shuffledSongs = List.from(value);
    notifyListeners();
  }

  set artWorkId(int id) {
    _artWorkId = id;
    notifyListeners();
  }

  set opacity(double op) {
    _opacity = op;
    notifyListeners();
  }

  set blur(double bl) {
    _prefs.setDouble("blur", bl);
    _blur = bl;
    notifyListeners();
  }

  /// Shuffle the song list, keeping the currently playing song at position 0.
  /// Does NOT restart playback — the current song continues uninterrupted.
  void shuffleSongs() {
    if (_songs.isEmpty) return;

    // Preserve the currently playing song
    final currentSong = (_songId >= 0 && _songId < _songs.length)
        ? _songs[_songId]
        : null;

    _shuffledSongs = List.from(_songs);
    _shuffledSongs.shuffle(math.Random());

    // Move the current song to index 0 so playback continues seamlessly
    if (currentSong != null) {
      _shuffledSongs.remove(currentSong);
      _shuffledSongs.insert(0, currentSong);
      _songId = 0;
    }

    notifyListeners();
  }

  /// Restore original (unshuffled) order, keeping the current song selected.
  void unshuffleSongs() {
    if (_songs.isEmpty) return;

    final currentSong = (_songId >= 0 && _songId < songs.length)
        ? songs[_songId]
        : null;

    // Find the song's position in the original list
    if (currentSong != null) {
      final origIdx = _songs.indexWhere((s) => s.id == currentSong.id);
      if (origIdx >= 0) _songId = origIdx;
    }

    notifyListeners();
  }

  set songId(int id) {
    _songId = id;
    notifyListeners();
    _loadLyricsForCurrentSong();
    // Check stem availability for new song
    if (songs.isNotEmpty && id >= 0 && id < songs.length) {
      stemController.onSongChanged(songs[id].data);
    }
  }

  Future<void> _loadLyricsForCurrentSong() async {
    if (songs.isEmpty || _songId < 0 || _songId >= songs.length) return;
    final targetId = _songId;
    // Skip if already loading for the same song (prevents double-call flicker)
    if (_lyricsLoadTarget == targetId) return;
    _lyricsLoadTarget = targetId;
    _lyricsLoading = true;
    _currentLyrics = null;
    notifyListeners();
    try {
      final result = await _lyricsService.loadLyrics(songs[targetId]);
      if (_songId != targetId) return;
      _currentLyrics = result;
    } catch (_) {
      if (_songId != targetId) return;
      _currentLyrics = null;
    }
    _lyricsLoadTarget = null;
    _lyricsLoading = false;
    notifyListeners();
  }

  /// Reloads lyrics for the current song (e.g. after editing/saving).
  Future<void> reloadCurrentLyrics() async {
    if (songs.isEmpty || _songId < 0 || _songId >= songs.length) return;
    _lyricsService.invalidateCache(songs[_songId].id);
    _lyricsLoadTarget = null; // force reload even if same song
    await _loadLyricsForCurrentSong();
  }

  /// Updates any song's in-memory metadata after tag writing.
  /// Mutates SongModel.getMap directly, invalidates artwork cache,
  /// and notifies all listeners so every screen rebuilds with fresh data.
  /// If the song is the currently playing track, also updates the media
  /// notification and reloads lyrics.
  Future<void> updateSongMetadata(
    SongModel song,
    RecognitionResult result, {
    String? newArtworkPath,
  }) async {
    // Mutate the in-memory SongModel fields
    if (result.title != null && result.title!.isNotEmpty) {
      song.getMap['title'] = result.title;
    }
    if (result.artist != null && result.artist!.isNotEmpty) {
      song.getMap['artist'] = result.artist;
    }
    if (result.album != null && result.album!.isNotEmpty) {
      song.getMap['album'] = result.album;
    }

    // If new artwork was fetched, save it to the UI cache location so
    // savedImage()/ArtworkWidget picks it up immediately.
    // For songs that already had artwork, TagWriter skips embedding (fill-empty),
    // but updating the cache with higher-quality Cover Art Archive art is fine.
    if (newArtworkPath != null && File(newArtworkPath).existsSync()) {
      try {
        final tempDir = await getTemporaryDirectory();
        final isCloud = song.data.startsWith('http');
        final cachePath = isCloud
            ? '${tempDir.path}/cloud_art_${song.id}.png'
            : '${tempDir.path}/${song.data.split('/').last.split('.').first}.png';
        final cacheFile = File(cachePath);
        if (cacheFile.existsSync()) cacheFile.deleteSync();
        File(newArtworkPath).copySync(cachePath);
      } catch (_) {}
    }

    // Invalidate fingerprint cache for this file
    fingerprintService.invalidateCache(song.data);

    notifyListeners();

    // If this is the currently playing song, also update notification + lyrics
    final isCurrentSong =
        songs.isNotEmpty &&
        _songId >= 0 &&
        _songId < songs.length &&
        songs[_songId].id == song.id;

    if (isCurrentSong) {
      _lyricsService.invalidateCache(song.id);
      _lyricsLoadTarget = null;
      loadAudioSource(_handler, song, replayGain: _replayGain);
      _loadLyricsForCurrentSong();
    }
  }

  void next() {
    if (songs.isEmpty) return;
    final loopMode = handler.player.loopMode;

    if (loopMode == LoopMode.one) {
      // Repeat-one: restart current track
      handler.player.seek(Duration.zero);
      handler.player.play();
      return;
    }

    if (songId >= songs.length - 1) {
      if (loopMode == LoopMode.all) {
        // Repeat-all: wrap to first song
        songId = 0;
        artWorkId = songs[0].id;
        loadAudioSource(handler, songs[0], replayGain: _replayGain);
      } else {
        // No repeat: stop at end
        songId = 0;
        handler.player.stop();
      }
    } else if (_gaplessPlayback && handler.player.audioSources.length > 1) {
      handler.player.seekToNext();
    } else {
      songId += 1;
      artWorkId = songs[songId].id;
      loadAudioSource(handler, songs[songId], replayGain: _replayGain);
    }
  }

  void prev() {
    if (songs.isEmpty) return;
    final loopMode = handler.player.loopMode;

    // If more than 3 seconds in, restart current track (standard behavior)
    final position = handler.player.position;
    if (position.inSeconds > 3) {
      handler.player.seek(Duration.zero);
      return;
    }

    if (loopMode == LoopMode.one) {
      handler.player.seek(Duration.zero);
      handler.player.play();
      return;
    }

    if (songId == 0) {
      if (loopMode == LoopMode.all) {
        // Repeat-all: wrap to last song
        songId = songs.length - 1;
        artWorkId = songs[songId].id;
        loadAudioSource(handler, songs[songId], replayGain: _replayGain);
      } else {
        // No repeat: restart first song
        handler.player.seek(Duration.zero);
      }
    } else if (_gaplessPlayback && handler.player.audioSources.length > 1) {
      handler.player.seekToPrevious();
    } else {
      songId -= 1;
      artWorkId = songs[songId].id;
      loadAudioSource(handler, songs[songId], replayGain: _replayGain);
    }
  }

  // --- Cloud services ---

  Future<void> _initCloudServices() async {
    await cloudCache.init();
    await cloudAuth.restoreGoogleSession();
    await cloudAuth.restoreDropboxSession();
    notifyListeners();
    // Kick off background metadata preload from cached file lists.
    _preloadMetadataFromCache();
  }

  /// Start background ID3 extraction for any cached cloud file lists.
  void _preloadMetadataFromCache() {
    if (isGoogleConnected) {
      final files = cloudCache.loadFileList(CloudProvider.googleDrive);
      if (files != null && files.isNotEmpty) {
        cloudMetadata.preloadAll(CloudProvider.googleDrive, files);
      }
    }
    if (isDropboxConnected) {
      final files = cloudCache.loadFileList(CloudProvider.dropbox);
      if (files != null && files.isNotEmpty) {
        cloudMetadata.preloadAll(CloudProvider.dropbox, files);
      }
    }
  }

  /// Trigger metadata preload for a provider's file list (called by CloudView
  /// after an API refresh saves a fresh file list).
  void preloadCloudMetadata(CloudProvider provider, List<CloudFile> files) {
    cloudMetadata.preloadAll(provider, files);
  }

  Future<bool> connectGoogle() async {
    final result = await cloudAuth.signInGoogle();
    notifyListeners();
    return result;
  }

  Future<void> disconnectGoogle() async {
    cloudMetadata.cancel(CloudProvider.googleDrive);
    await cloudAuth.signOutGoogle();
    notifyListeners();
  }

  Future<bool> connectDropbox() async {
    final result = await cloudAuth.signInDropbox();
    notifyListeners();
    return result;
  }

  Future<void> disconnectDropbox() async {
    cloudMetadata.cancel(CloudProvider.dropbox);
    await cloudAuth.signOutDropbox();
    notifyListeners();
  }

  /// Pre-cache the next [count] cloud tracks in the queue.
  void preCacheNextCloudTracks({int count = 2}) {
    for (int i = songId + 1; i <= songId + count && i < songs.length; i++) {
      final song = songs[i];
      if (!song.data.startsWith('http')) continue;
      final fileId = song.id.toString();
      if (cloudCache.isCached(fileId)) continue;
      // Fire-and-forget
      _preCacheSingle(song, fileId);
    }
  }

  Future<void> _preCacheSingle(SongModel song, String fileId) async {
    try {
      final headers = song.data.contains('googleapis.com')
          ? await cloudAuth.getGoogleAuthHeaders()
          : <String, String>{};
      await cloudCache.preCacheTrack(song.data, fileId, headers);
    } catch (_) {}
  }
}
