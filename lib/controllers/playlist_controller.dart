import '/models/OnlineSongModel.dart';
import 'package:flutter/material.dart';

class PlaylistController with ChangeNotifier {
  List<OnlineSongModel> _onlineSongs = [];
  List<OnlineSongModel> get onlineSongs => _onlineSongs;
  set onlineSongs(List<OnlineSongModel> onlineSongs) {
    _onlineSongs = onlineSongs;
    notifyListeners();
  }
}
