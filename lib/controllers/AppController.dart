import 'dart:async';
import 'dart:math' as math;

import 'package:eq_app/Global/index.dart';
import '/exports/exports.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Helpers/AudioHandler.dart';
import '../Helpers/Channel.dart';
import '../Helpers/index.dart';

class AppController with ChangeNotifier {
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
  }

  /// Subscribe to the active player's processingStateStream.
  /// Called once at init and again after every crossfade swap.
  void _bindProcessingState() {
    _processingSub?.cancel();
    _processingSub = handler.player.processingStateStream.listen((event) {
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
  void _bindCurrentIndex() {
    _indexSub?.cancel();
    _indexSub = handler.player.currentIndexStream.listen((index) {
      if (index != null && _gaplessPlayback && songs.isNotEmpty && index < songs.length) {
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

    // Update songId/artWorkId immediately so the deck switches.
    // Don't call notifyListeners() here — handler.beginCrossfade will
    // fire onCrossfadeStarted after the new track is loaded on the
    // incoming player, at which point currentTrackPlayer returns the
    // correct player for the waveform.
    _songId = nextIdx;
    _artWorkId = nextSong.id;

    await handler.beginCrossfade(
      AudioSource.uri(Uri.parse(nextSong.data)),
      nextSong,
      Duration(seconds: _crossfadeDuration),
      replayGain: _replayGain,
    );
    _isCrossfading = false;
  }

  Future<void> _updateMediaItemForIndex(int index) async {
    if (index >= songs.length) return;
    final song = songs[index];
    final image = await fetchArtworkUrl(song.data, song.id);
    handler.setCurrentMediaItem(MediaItem(
      id: song.data,
      album: song.album,
      title: song.title,
      artist: song.artist,
      duration: Duration(milliseconds: song.duration ?? 0),
      artUri: Uri.file(image),
    ));
  }

  /// Build and load a queue for gapless playback
  Future<void> loadGaplessQueue(int startIndex) async {
    if (songs.isEmpty) return;
    final sources = songs.map((s) => AudioSource.uri(Uri.parse(s.data))).toList();
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
}
