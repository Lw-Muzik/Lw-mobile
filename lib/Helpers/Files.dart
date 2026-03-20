import 'dart:io';
import '/exports/exports.dart';
import '/services/local_music_scanner.dart';

class Files {
  static Future<List<SongModel>> queryFromFolder(String path) async {
    List<SongModel> filteredSongs = [];

    var songs = await _getAllSongs();
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
    if (Platform.isIOS) {
      final songs = await _getAllSongs();
      songs.sort((a, b) => (b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0));
      return songs;
    }
    return await OnAudioQuery().querySongs(
      sortType: SongSortType.DATE_ADDED,
      orderType: OrderType.DESC_OR_GREATER,
      uriType: UriType.INTERNAL,
    );
  }

  // function to fetch all songs
  static Future<List<SongModel>> fetchAllSongs() async {
    return _getAllSongs();
  }

  /// Merges MPMediaQuery results with local file scanner results on iOS.
  static Future<List<SongModel>> _getAllSongs() async {
    List<SongModel> songs;
    try {
      songs = await OnAudioQuery().querySongs();
    } catch (_) {
      songs = [];
    }

    if (Platform.isIOS) {
      try {
        final localSongs = await LocalMusicScanner.scanLocalFiles();
        if (localSongs.isNotEmpty) {
          final existingPaths = songs.map((s) => s.data).toSet();
          final newLocal =
              localSongs.where((s) => !existingPaths.contains(s.data));
          songs = [...songs, ...newLocal];
        }
      } catch (_) {}
    }

    return songs;
  }
}
