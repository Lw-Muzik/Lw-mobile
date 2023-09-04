import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

class AppController with ChangeNotifier {
  int _songId = 0;
  bool _isLoop = false;
  int _artWorkId = 0;
  // Main method.
  final OnAudioQuery _audioQuery = OnAudioQuery();
  double _opacity = 0.0;
  double _blur = 50;

  final AudioPlayer _audioPlayer = AudioPlayer();
  List<SongModel> _songs = [];
  AppController() {
    _audioPlayer.playerStateStream.listen((event) {
      if (event.processingState == ProcessingState.completed) {
        songId += 1;
        if (songId > songs.length + 1) {
          songId = 0;
          artWorkId = songs[songId].id;
          _audioPlayer.setUrl(songs[songId].data);
          _audioPlayer.play();
        } else {
          artWorkId = songs[songId].id;
          _audioPlayer.setUrl(songs[songId].data);
          _audioPlayer.play();
        }
      }
    });
  }

  int get songId => _songId;
  double get opacity => _opacity;
  double get blur => _blur;
  int get artWorkId => _artWorkId;
  List<SongModel> get songs => _songs;
  AudioPlayer get audioPlayer => _audioPlayer;
  OnAudioQuery get audioQuery => _audioQuery;

  set songs(List<SongModel> value) {
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
    _blur = bl;
    notifyListeners();
  }

  set songId(int value) {
    _songId = value;
    notifyListeners();
  }

  void next() {
    songId += 1;
    artWorkId = songs[songId].id;
    _audioPlayer.setUrl(songs[songId].data);
    _audioPlayer.play();
  }

  void prev() {
    songId -= 1;
    artWorkId = songs[songId].id;
    _audioPlayer.setUrl(songs[songId].data);
    _audioPlayer.play();
  }
}
