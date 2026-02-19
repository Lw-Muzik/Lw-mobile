import 'dart:math' as math;

import 'package:eq_app/Global/index.dart';
import '/exports/exports.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Helpers/AudioHandler.dart';

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

  final AudioHandler _handler = AudioHandler();
  AudioHandler get handler => _handler;
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
  int _songId = 0;
  int _artWorkId = 0;
  // Main method.
  final OnAudioQuery _audioQuery = OnAudioQuery();
  double _opacity = 0.0;
  double _blur = 40;

  final SharedPreferences _prefs;
  List<SongModel> _songs = [];
  List<SongModel> _shuffledSongs = [];

  AppController(this._prefs) {
    _loadSettings();

    handler.player.processingStateStream.listen((event) {
      if (event == ProcessingState.completed) {
        if (songId >= songs.length - 1) {
          handler.player.stop();
        } else {
          songId += 1;
          artWorkId = songs[songId].id;
          loadAudioSource(handler, songs[songId]);
        }
      }
    });
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
    loadAudioSource(handler, sample[0]);
  }

  set songId(int id) {
    _songId = id;
    notifyListeners();
  }

  void next() {
    if (songId >= songs.length - 1) {
      songId = 0;
      handler.player.stop();
    } else {
      songId += 1;
      artWorkId = songs[songId].id;
      loadAudioSource(handler, songs[songId]);
    }
  }

  void prev() {
    if (songId == 0) {
      songId = 0;
      handler.player.stop();
    } else {
      songId -= 1;
      artWorkId = songs[songId].id;
      loadAudioSource(handler, songs[songId]);
    }
  }
}
