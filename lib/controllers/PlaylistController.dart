import 'package:eq_app/controllers/AppController.dart';
import 'package:eq_app/models/OnlineSongModel.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

class PlaylistController with ChangeNotifier {
  final AppController controller = AppController();
  List<OnlineSongModel> _onlineSongs = [];
  List<OnlineSongModel> get onlineSongs => _onlineSongs;
  set onlineSongs(List<OnlineSongModel> onlineSongs) {
    _onlineSongs = onlineSongs;
    notifyListeners();
  }

  void loadOnlineJams(int i) {
    var playlist = ConcatenatingAudioSource(
      children: List.generate(
        onlineSongs.length,
        (index) => AudioSource.uri(
          Uri.parse(onlineSongs[i].url),
          tag: MediaItem(
            id: onlineSongs[index].url,
            title: onlineSongs[index].title,
            artist: onlineSongs[index].artist,
            album: onlineSongs[index].artWork,
            artUri: Uri.parse(onlineSongs[index].artWork),
          ),
        ),
      ),
    );
    controller.audioHandler.setAudioSource(playlist);
    controller.audioHandler.play();
  }
}
