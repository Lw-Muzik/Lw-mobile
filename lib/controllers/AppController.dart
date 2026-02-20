import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:eq_app/Global/index.dart';
import '/exports/exports.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Helpers/AudioHandler.dart';
import '../Helpers/Channel.dart';
import '../Helpers/index.dart';
import '../models/eq_models.dart';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/cloud_file.dart';
import '../services/cloud_auth_service.dart';
import '../services/cloud_cache_service.dart';
import '../services/cloud_metadata_service.dart';
import '../services/google_drive_service.dart';
import '../services/dropbox_service.dart';

class AppController with ChangeNotifier {
  static AppController? _instance;
  static AppController get instance => _instance!;

  // Cloud services
  late final CloudAuthService cloudAuth;
  late final CloudCacheService cloudCache;
  late final CloudMetadataService cloudMetadata;
  late final GoogleDriveService googleDriveService;
  late final DropboxService dropboxService;

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

  // DSP settings
  bool _enableDSP = false;
  int _selectSpeaker = -1;
  String _spkName = "BEATS BY DRE";
  double _dspVolume = -6.0;
  double _dspXTreble = 3.3;
  double _dspPowerBass = 8.0;
  double _dspXBass = 11.0;
  double _dspXBass2 = 13.0;
  double _dspOutGain = 3.0;
  double _dspNoise = -10.0;
  // DSP COMPRESSOR
  double _threshold = -2.0;
  double _ratio = 10.0;
  double _attackTime = 1;
  double _releaseTime = 60;
  double _kneeWidth = 0.40;
  double _expandRatio = 15.0;
  double _preGain = 20;
  // bass freq
  double _bassFreq = 50;
  double _vocalFreq = 450;

  // Audio feature settings
  bool _gaplessPlayback = true;
  int _crossfadeDuration = 0; // seconds, 0 = off
  bool _replayGain = false;
  bool _dvcEnabled = false;
  double _dvcGain = 0.0; // dB, range -30 to +30

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

  void updateParametricPoint(int index, {double? frequency, double? gain, bool? enabled}) {
    if (index >= 0 && index < _parametricPoints.length) {
      _parametricPoints[index] = _parametricPoints[index].copyWith(
        frequency: frequency,
        gain: gain,
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
    for (int i = 0; i < _parametricPoints.length && i < 32; i++) {
      freqs[i] = _parametricPoints[i].frequency;
      gains[i] = _parametricPoints[i].enabled ? _parametricPoints[i].gain : 0.0;
    }
    Channel.setParametricAllBands(freqs, gains);
  }

  void _persistGraphicGains() {
    _prefs.setString("graphicBandGains", json.encode(_graphicBandGains));
  }

  void _persistParametricPoints() {
    _prefs.setString("parametricPoints",
        json.encode(_parametricPoints.map((p) => p.toJson()).toList()));
  }

  Future<void> detectAndApplyDevicePreset() async {
    final device = await Channel.getAudioOutputType();
    if (device != _lastOutputDevice && !_linkAllDevices) {
      // Save current for old device
      _savedPresets['_device_$_lastOutputDevice'] = EqPreset(
        name: '_device_$_lastOutputDevice',
        graphicGains: List<double>.from(_graphicBandGains),
        parametric: _parametricPoints.map((p) => p.copyWith()).toList(),
        deviceType: _lastOutputDevice,
      );
      _prefs.setString("eqPresets", EqPreset.encodeList(_savedPresets));

      // Load preset for new device if it exists
      final devicePreset = _savedPresets['_device_$device'];
      if (devicePreset != null) {
        setGraphicAllBands(devicePreset.graphicGains);
        _parametricPoints = devicePreset.parametric.map((p) => p.copyWith()).toList();
        _applyParametricToNative();
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
    Channel.enableLoudnessEnhancer(value);
    notifyListeners();
  }

  set dvcGain(double value) {
    _prefs.setDouble("dvcGain", value);
    _dvcGain = value;
    Channel.setTargetGain((value * 100).toInt()); // API expects millibels
    notifyListeners();
  }

  // DSP getters
  bool get enableDSP => _enableDSP;
  String get spkName => _spkName;
  int get selectSpeaker => _selectSpeaker;
  double get dspVolume => _dspVolume;
  double get dspXTreble => _dspXTreble;
  double get dspNoise => _dspNoise;
  double get dspPowerBass => _dspPowerBass;
  double get dspXBass => _dspXBass;
  double get dspXBass2 => _dspXBass2;
  double get dspOutGain => _dspOutGain;

  // compressor
  double get threshold => _threshold;
  double get attackTime => _attackTime;
  double get ratio => _ratio;
  double get preGain => _preGain;
  double get kneeWidth => _kneeWidth;
  double get expandRatio => _expandRatio;
  double get releaseTime => _releaseTime;
  double get bassFreq => _bassFreq;
  double get vocalFreq => _vocalFreq;

  // compressor setters
  set threshold(double threshold) {
    _prefs.setDouble("threshold", threshold);
    _threshold = threshold;
    notifyListeners();
  }

  set spkName(String name) {
    _prefs.setString("spkName", name);
    _spkName = name;
    notifyListeners();
  }

  set attackTime(double attackTime) {
    _prefs.setDouble("attackTime", attackTime);
    _attackTime = attackTime;
    notifyListeners();
  }

  set preGain(double gain) {
    _prefs.setDouble("preGain", gain);
    _preGain = gain;
    notifyListeners();
  }

  set kneeWidth(double width) {
    _prefs.setDouble("kneeWidth", width);
    _kneeWidth = width;
    notifyListeners();
  }

  set expandRatio(double ratio) {
    _prefs.setDouble("expandRatio", ratio);
    _expandRatio = ratio;
    notifyListeners();
  }

  set ratio(double ratio) {
    _prefs.setDouble("ratio", ratio);
    _ratio = ratio;
    notifyListeners();
  }

  set releaseTime(double r) {
    _prefs.setDouble("releaseTime", r);
    _releaseTime = r;
    notifyListeners();
  }

  set bassFreq(double freq) {
    _prefs.setDouble("bassFreq", freq);
    _bassFreq = freq;
    notifyListeners();
  }

  set vocalFreq(double freq) {
    _prefs.setDouble("vocalFreq", freq);
    _vocalFreq = freq;
    notifyListeners();
  }

  // DSP setters
  set enableDSP(bool dsp) {
    _prefs.setBool("enableDSP", dsp);
    _enableDSP = dsp;
    notifyListeners();
  }

  set dspNoise(double noise) {
    _prefs.setDouble("dspNoise", noise);
    _dspNoise = noise;
    notifyListeners();
  }

  set selectSpeaker(int dsp) {
    _prefs.setInt("selectedSpeaker", dsp);
    _selectSpeaker = dsp;
    notifyListeners();
  }

  set dspVolume(double vol) {
    _prefs.setDouble("dspVolume", vol);
    _dspVolume = vol;
    notifyListeners();
  }

  set dspXTreble(double xtreble) {
    _prefs.setDouble("xTreble", xtreble);
    _dspXTreble = xtreble;
    notifyListeners();
  }

  set dspPowerBass(double powerBass) {
    _prefs.setDouble("powerBass", powerBass);
    _dspPowerBass = powerBass;
    notifyListeners();
  }

  set dspXBass(double xBass) {
    _prefs.setDouble("xBass", xBass);
    _dspXBass = xBass;
    notifyListeners();
  }

  set dspXBass2(double xBass2) {
    _dspXBass2 = xBass2;
    notifyListeners();
  }

  set dspOutGain(double gain) {
    _prefs.setDouble("powerGain", gain);
    _dspOutGain = gain;
    notifyListeners();
  }

  //----------- end of dsp initialization --------------------------------

  bool _dspSpeakerView = false;
  bool get dspSpeakerView => _dspSpeakerView;
  set dspSpeakerView(bool dspView) {
    _dspSpeakerView = dspView;
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
      Channel.enableLoudnessEnhancer(true);
      Channel.setTargetGain((_dvcGain * 100).toInt());
    }

    _bindProcessingState();
    _bindCurrentIndex();
    _setupCrossfadeListener();
    _bindAudioSessionId();

    // Cloud services
    _instance = this;
    cloudAuth = CloudAuthService();
    cloudCache = CloudCacheService(_prefs);
    googleDriveService = GoogleDriveService(cloudAuth);
    dropboxService = DropboxService(cloudAuth);
    cloudMetadata = CloudMetadataService(
        cloudAuth, cloudCache, googleDriveService, dropboxService);
    _initCloudServices();
  }

  /// Listen to audio session ID changes and rebind all native effects.
  /// This runs for the lifetime of the app, not just while the Equalizer page is open.
  void _bindAudioSessionId() {
    _sessionIdSub?.cancel();
    _sessionIdSub = _handler.player.androidAudioSessionIdStream.listen((sessionId) {
      if (sessionId != null) {
        Channel.setSessionId(sessionId);
        // Re-apply current graphic EQ bands to the new session
        if (_graphicEqEnabled) {
          Channel.setGraphicAllBands(_graphicBandGains);
          Channel.enableEq(true);
          Channel.enableDSPEngine(true);
        }
      }
    });
  }

  /// Subscribe to the active player's processingStateStream.
  /// Called once at init and again after every crossfade swap.
  void _bindProcessingState() {
    _processingSub?.cancel();
    _processingSub = handler.player.processingStateStream.listen((event) {
      if (event == ProcessingState.ready) {
        preCacheNextCloudTracks();
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

    final AudioSource nextSource;
    if (nextSong.data.startsWith('http')) {
      final fileId = nextSong.id.toString();
      if (cloudCache.isCached(fileId)) {
        nextSource = AudioSource.file(cloudCache.cacheFile(fileId).path);
      } else {
        final headers = nextSong.data.contains('googleapis.com')
            ? await cloudAuth.getGoogleAuthHeaders()
            : <String, String>{};
        nextSource = LockCachingAudioSource(Uri.parse(nextSong.data),
            cacheFile: cloudCache.cacheFile(fileId), headers: headers);
      }
    } else {
      nextSource = AudioSource.uri(Uri.parse(nextSong.data));
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
    handler.setCurrentMediaItem(MediaItem(
      id: song.data,
      album: song.album,
      title: song.title,
      artist: song.artist,
      duration: Duration(milliseconds: song.duration ?? 0),
      artUri: artUri,
    ));
  }

  Future<String?> _downloadCloudArtwork(String url, int songId) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file =
          File('${tempDir.path}/cloud_art_$songId.png');
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

  /// Build and load a queue for gapless playback
  Future<void> loadGaplessQueue(int startIndex) async {
    if (songs.isEmpty) return;
    final sources = <AudioSource>[];
    for (final s in songs) {
      if (s.data.startsWith('http')) {
        final fileId = s.id.toString();
        if (cloudCache.isCached(fileId)) {
          sources.add(AudioSource.file(cloudCache.cacheFile(fileId).path));
        } else {
          final headers = s.data.contains('googleapis.com')
              ? await cloudAuth.getGoogleAuthHeaders()
              : <String, String>{};
          sources.add(LockCachingAudioSource(Uri.parse(s.data),
              cacheFile: cloudCache.cacheFile(fileId), headers: headers));
        }
      } else {
        sources.add(AudioSource.uri(Uri.parse(s.data)));
      }
    }
    await handler.player.setAudioSources(sources, initialIndex: startIndex);
    await _updateMediaItemForIndex(startIndex);
    handler.player.play();
  }

  void _loadSettings() {
    _enableEffects = _prefs.getBool("enableEffects") ?? false;
    _enableDSP = _prefs.getBool("enableDSP") ?? false;
    _selectSpeaker = _prefs.getInt("selectedSpeaker") ?? -1;
    _dspVolume = _prefs.getDouble("dspVolume") ?? -6.0;
    _dspXTreble = _prefs.getDouble("xTreble") ?? 3.3;
    _dspPowerBass = _prefs.getDouble("powerBass") ?? 8.0;
    _dspXBass = _prefs.getDouble("xBass") ?? 11.0;
    _dspOutGain = _prefs.getDouble("powerGain") ?? 3.0;
    _selectedPreset = _prefs.getInt("selectedPreset") ?? 0;
    _isFancy = _prefs.getBool("fancyMode") ?? false;
    _isShuffled = _prefs.getBool("isShuffled") ?? false;
    _isVisualInBackground = _prefs.getBool("isVisualInBackground") ?? false;
    _visuals = _prefs.getBool("visuals") ?? false;
    _bgQuality = _prefs.getDouble("bgQuality") ?? 2.0;
    _blur = _prefs.getDouble("blur") ?? 40.0;
    _selectedRoomPreset = _prefs.getInt("selectedRoomPreset") ?? 0;
    // compressors
    _threshold = _prefs.getDouble("threshold") ?? -2.0;
    _ratio = _prefs.getDouble("ratio") ?? 10.0;
    _attackTime = _prefs.getDouble("attackTime") ?? 1.0;
    _releaseTime = _prefs.getDouble("releaseTime") ?? 60.0;
    _bassFreq = _prefs.getDouble("bassFreq") ?? 50.0;
    _vocalFreq = _prefs.getDouble("vocalFreq") ?? 450.0;
    _dspNoise = _prefs.getDouble("dspNoise") ?? 0.0;
    _expandRatio = _prefs.getDouble("expandRatio") ?? 15.0;
    _preGain = _prefs.getDouble("preGain") ?? 20.0;
    _kneeWidth = _prefs.getDouble("kneeWidth") ?? 0.4;
    _spkName = _prefs.getString("spkName") ?? "BEATS BY DRE";
    // Audio features
    _gaplessPlayback = _prefs.getBool("gaplessPlayback") ?? true;
    _crossfadeDuration = _prefs.getInt("crossfadeDuration") ?? 0;
    _replayGain = _prefs.getBool("replayGain") ?? false;
    _dvcEnabled = _prefs.getBool("dvcEnabled") ?? false;
    _dvcGain = _prefs.getDouble("dvcGain") ?? 0.0;
    // EQ band count
    _eqBandCount = _prefs.getInt("eqBandCount") ?? 32;
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

  int get songId {
    return _songId;
  }

  int get selectedRoomPreset => _selectedRoomPreset;
  set selectedRoomPreset(int x) {
    _prefs.setInt("selectedRoomPreset", x);
    _selectedRoomPreset = x;
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
    _shuffledSongs = value;
    _songs = value;
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

  void shuffleSongs() {
    List sample = shuffledSongs;
    final random = math.Random();
    for (var i = 0; i < sample.length; i++) {
      final j = random.nextInt(i + 1);
      final temp = sample[i];
      sample[i] = sample[j];
      sample[j] = temp;
    }
    songId = 0;
    if (_gaplessPlayback && _crossfadeDuration == 0) {
      loadGaplessQueue(0);
    } else {
      loadAudioSource(handler, sample[0], replayGain: _replayGain);
    }
  }

  set songId(int id) {
    _songId = id;
    notifyListeners();
  }

  void next() {
    if (songId >= songs.length - 1) {
      songId = 0;
      handler.player.stop();
    } else if (_gaplessPlayback && handler.player.audioSources.length > 1) {
      handler.player.seekToNext();
    } else {
      songId += 1;
      artWorkId = songs[songId].id;
      loadAudioSource(handler, songs[songId], replayGain: _replayGain);
    }
  }

  void prev() {
    if (songId == 0) {
      songId = 0;
      handler.player.stop();
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
