import '/exports/exports.dart';

class Files {
  static Future<List<SongModel>> queryFromFolder(String path) async {
    List<SongModel> filteredSongs = [];

    var songs = await OnAudioQuery().querySongs();
    filteredSongs = songs
        .where(
          (s) =>
              s.data.split("/")[s.data.split("/").length - 2] ==
              path.split("/").last,
        )
        .toList();

    return filteredSongs;
  }

  // function fetch most recent songs added
  static Future<List<SongModel>> fetchMostRecentlyPlayed() async {
    return await OnAudioQuery().querySongs(
      sortType: SongSortType.DATE_ADDED,
      orderType: OrderType.DESC_OR_GREATER,
      uriType: UriType.INTERNAL,
    );
  }

  // function to fetch all songs
  static Future<List<SongModel>> fetchAllSongs() async {
    return await OnAudioQuery().querySongs();
  }
}
