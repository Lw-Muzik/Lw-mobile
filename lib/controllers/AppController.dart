import 'dart:math' as math;
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppController extends ChangeNotifier {
  List<int> _bandValues = [0, 0, 0, 0, 0];
  // app themes
  String _selectedTheme = "light";
  bool _isDark = false;
  bool _playerVisual = false;
  // Player controller
  final PageController _pageController = PageController();
  PageController get pageController => _pageController;
  //
  bool _enableEffects = false;
  bool get enableEffects {
    SharedPreferences.getInstance().asStream().listen((event) {
      _enableEffects = event.getBool("enableEffects") ?? false;
      notifyListeners();
    });
    return _enableEffects;
  }

  set enableEffects(bool value) {
    SharedPreferences.getInstance().asStream().listen((event) {
      event.setBool("enableEffects", value);
    });
    _enableEffects = value;
    notifyListeners();
  }

  int _selectedRoomPreset = -1;
  /*
     private static final float out_gain = 0.0f;
    private static final float dsp_volume = -8.0f;
    private static final float dsp_powerBass = 8.0f;
    private static final float dsp_xBass = 11.0f;
    private static final float dsp_treble = 3.3f*/
  // DSP settings
  bool _enableDSP = false;
  int _selectSpeaker = -1;
  double _dspVolume = -6.0;
  double _dspXTreble = 3.3;
  double _dspPowerBass = 8.0;
  double _dspXBass = 11.0;
  double _dspXBass2 = 13.0;
  double _dspOutGain = 3.0;
  // DSP getters
  bool get enableDSP {
    SharedPreferences.getInstance().asStream().listen((event) {
      _enableDSP = event.getBool("enableDSP") ?? false;
      notifyListeners();
    });
    return _enableDSP;
  }

  int get selectSpeaker {
    //   SharedPreferences.getInstance().asStream().listen((event) {
    //   _enableDSP = event.getBool("enableDSP") ?? false;
    //   notifyListeners();
    // });
    return _selectSpeaker;
  }

  double get dspVolume {
    // SharedPreferences.getInstance().asStream().listen((event) {
    //   _dspVolume = event.getDouble("dspVolume") ?? -6.0;
    //   notifyListeners();
    // });
    return _dspVolume;
  }

  double get dspXTreble {
    // SharedPreferences.getInstance().asStream().listen((event) {
    //   _dspXTreble = event.getDouble("xTreble") ?? 3.3;
    //   notifyListeners();
    // });
    return _dspXTreble;
  }

  double get dspPowerBass {
    // SharedPreferences.getInstance().asStream().listen((event) {
    //   _dspPowerBass = event.getDouble("powerBass") ?? 8.0;
    //   notifyListeners();
    // });
    return _dspPowerBass;
  }

  double get dspXBass {
    // SharedPreferences.getInstance().asStream().listen((event) {
    //   _dspXBass = event.getDouble("xBass") ?? 11.0;
    //   notifyListeners();
    // });
    return _dspXBass;
  }

  double get dspXBass2 {
    return _dspXBass2;
  }

  double get dspOutGain {
    // SharedPreferences.getInstance().asStream().listen((event) {
    //   _dspOutGain = event.getDouble("powerGain") ?? 3.0;

    //   notifyListeners();
    // });
    return _dspOutGain;
  }

  // DSP setters
  set enableDSP(bool dsp) {
    SharedPreferences.getInstance().asStream().listen((event) {
      event.setBool("enableDSP", dsp);
    });
    _enableDSP = dsp;
    notifyListeners();
  }

  set selectSpeaker(int dsp) {
    _selectSpeaker = dsp;
    notifyListeners();
  }

  set dspVolume(double vol) {
    SharedPreferences.getInstance().asStream().listen((event) {
      event.setDouble("dspVolume", vol);
    });
    _dspVolume = vol;
    notifyListeners();
  }

  set dspXTreble(double xtreble) {
    SharedPreferences.getInstance().asStream().listen((event) {
      event.setDouble("xTreble", xtreble);
    });
    _dspXTreble = xtreble;
    notifyListeners();
  }

  set dspPowerBass(double powerBass) {
    SharedPreferences.getInstance().asStream().listen((event) {
      event.setDouble("powerBass", powerBass);
    });
    _dspPowerBass = powerBass;
    notifyListeners();
  }

  set dspXBass(double xBass) {
    SharedPreferences.getInstance().asStream().listen((event) {
      event.setDouble("xBass", xBass);
    });
    _dspXBass = xBass;
    notifyListeners();
  }

  set dspXBass2(double xBass2) {
    _dspXBass2 = xBass2;
    notifyListeners();
  }

  set dspOutGain(double gain) {
    SharedPreferences.getInstance().asStream().listen((event) {
      event.setDouble("powerGain", gain);
    });
    _dspOutGain = gain;
    notifyListeners();
  }

  //----------- end of dsp initialization --------------------------------
  List<PlaylistModel> _playlist = [];
  List<PlaylistModel> get playlist => _playlist;
  set playlist(List<PlaylistModel> _plst) {
    _playlist = _plst;
    notifyListeners();
  }

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
  double _blur = 10;

  final AudioPlayer _audioPlayer = AudioPlayer();
  List<SongModel> _songs = [];
  List<SongModel> _shuffledSongs = [];
  AppController() {
    _audioPlayer.playerStateStream.listen((event) {
      if (event.processingState == ProcessingState.completed) {
        if (songId >= songs.length - 1) {
          _audioPlayer.stop();
        } else {
          songId += 1;
          // if (pageController.hasClients) {
          //   pageController.animateToPage(
          //     songId,
          //     duration: const Duration(milliseconds: 1100),
          //     curve: Curves.decelerate,
          //   );
          artWorkId = _songs[songId].id;
          _audioPlayer.setUrl(_songs[songId].data);
          _audioPlayer.play();
          // }
        }
      }
    });
  }
  bool get isDark {
    // SharedPreferences.getInstance().then((value) {
    //   bool k = value.getBool("isDark") ?? false;
    //   _isDark = k;
    //   notifyListeners();
    // });
    return _isDark;
  }

  List<int> get bandValues => _bandValues;
  set bandValues(List<int> bandLevels) {
    _bandValues = bandLevels;
    notifyListeners();
  }

  bool get isShuffled => _isShuffled;

  int get selectedPreset {
    // SharedPreferences.getInstance().then((value) {
    //   int p = value.getInt("selectedPreset") ?? 0;
    //   _selectedPreset = p;
    //   notifyListeners();
    // });
    return _selectedPreset;
  }

  bool get playerVisual => _playerVisual;
  double get bgQuality => _bgQuality;
  bool get isFancy {
    // SharedPreferences.getInstance().then((value) {
    //   bool f = value.getBool("isFancy") ?? false;
    //   _isFancy = f;
    //   notifyListeners();
    // });
    return _isFancy;
  }

  String get selectedTheme {
    // SharedPreferences.getInstance().then((value) {
    //   String isD = value.getString("selectedTheme") ?? "light";
    //   _selectedTheme = isD;
    //   notifyListeners();
    // });
    return _selectedTheme;
  }

  bool get isVisualInBackground => _isVisualInBackground;

  int get songId {
    // SharedPreferences.getInstance().then((value) {
    //   int sId = value.getInt("songId") ?? 0;
    //   _songId = sId;
    //   notifyListeners();
    // });
    return _songId;
  }

  int get selectedRoomPreset => _selectedRoomPreset;
  set selectedRoomPreset(int x) {
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
  AudioPlayer get audioPlayer => _audioPlayer;
  OnAudioQuery get audioQuery => _audioQuery;

  set visuals(bool v) {
    _visuals = v;
    notifyListeners();
  }

  set isShuffled(bool sh) {
    _isShuffled = sh;
    notifyListeners();
  }

  set selectedTheme(String t) {
    SharedPreferences.getInstance().then((value) {
      value.setString("selectedTheme", t);
    });
    _selectedTheme = t;
    notifyListeners();
  }

// ========================
  set selectedPreset(int pr) {
    SharedPreferences.getInstance().then((value) {
      value.setInt("selectedPreset", pr);
      _selectedPreset = pr;
      notifyListeners();
    });
  }

  set playerVisual(bool pV) {
    _playerVisual = pV;
    notifyListeners();
  }

  /// adjusting player's background
  set bgQuality(double q) {
    _bgQuality = q;
    notifyListeners();
  }

  set isVisualInBackground(bool b) {
    _isVisualInBackground = b;
    notifyListeners();
  }

  set isFancy(bool fancy) {
    // SharedPreferences.getInstance().then((value) {
    //   value.setBool("isFancy", fancy);
    // });
    _isFancy = fancy;
    notifyListeners();
  }

  set songs(List<SongModel> value) {
    _shuffledSongs = value;
    _songs = value;
    notifyListeners();
  }

  set artWorkId(int id) {
    // SharedPreferences.getInstance().then((value) {
    //   value.setInt("artWorkId", id);
    // });
    _artWorkId = id;
    notifyListeners();
  }

  set opacity(double op) {
    _opacity = op;
    notifyListeners();
  }

  set blur(double bl) {
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
    _audioPlayer.setUrl(sample[0].data);
    _audioPlayer.play();
  }

  set songId(int id) {
    // SharedPreferences.getInstance().then((value) {
    //   value.setInt("songId", id);
    //   notifyListeners();
    // });
    _songId = id;
    notifyListeners();
  }

  void next() {
    if (songId >= songs.length) {
      songId = 0;
      _audioPlayer.stop();
    } else {
      songId += 1;

      artWorkId = _songs[songId].id;
      _audioPlayer.setUrl(_songs[songId].data);
      _audioPlayer.play();
    }
  }

  void prev() {
    if (songId == 0) {
      songId = 0;
      _audioPlayer.stop();
    } else {
      songId -= 1;

      artWorkId = _songs[songId].id;
      _audioPlayer.setUrl(_songs[songId].data);
      _audioPlayer.play();
    }
  }
}
