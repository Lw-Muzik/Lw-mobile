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

    return filteredSongs;
  }

  // function fetch most recent songs added
  static Future<List<SongModel>> fetchMostRecentlyPlayed() async {
    List<SongModel> recents = [];
    var songs = await OnAudioQuery().querySongs(
        sortType: SongSortType.DATE_ADDED,
        orderType: OrderType.DESC_OR_GREATER,
        uriType: UriType.INTERNAL);
    // Sort the music files by modification time in descending order to get the most recent ones
    // songs.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    recents = songs.where((element) => true).toList();
    return recents;
  }

  // function to fetch all songs
  static Future<List<SongModel>> fetchAllSongs() async {
    List<SongModel> allSongs = [];
    var s = await OnAudioQuery().querySongs();
    allSongs = s.where((element) => true).toList();
    return allSongs;
  }
}
