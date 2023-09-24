import 'package:on_audio_query/on_audio_query.dart';

class Files {
  static Future<List<SongModel>> queryFromFolder(String path) async {
    List<SongModel> filteredSongs = [];

    var songs = await OnAudioQuery().querySongs();
    filteredSongs = songs
        .where((s) =>
            s.data.split("/")[s.data.split("/").length - 2] ==
            path.split("/").last)
        .toList();
    // for (var song in filteredSongs) {
    //   var parser = ID3TagReader.path(song.data);
    //   var tag = parser.readTagSync();
    //   print(tag.lyrics);
    // }
    return filteredSongs;
  }
}
