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

  static Future<List<SongModel>> fetchAllSongs() async {
    return _getAllSongs();
  }

  /// Fetch albums — on iOS, derive from local songs if MPMediaQuery is empty.
  static Future<List<AlbumModel>> fetchAllAlbums() async {
    try {
      final albums = await OnAudioQuery().queryAlbums();
      if (albums.isNotEmpty) return albums;
    } catch (_) {}

    if (!Platform.isIOS) return [];

    // Derive from local songs
    final songs = await _getAllSongs();
    final albumMap = <String, Map<String, dynamic>>{};
    for (final s in songs) {
      final name = (s.album != null && s.album!.isNotEmpty)
          ? s.album!
          : 'Unknown Album';
      albumMap.putIfAbsent(name, () => {
        "_id": name.hashCode.abs(),
        "album": name,
        "artist": s.artist ?? 'Unknown Artist',
        "artist_id": (s.artist ?? 'Unknown Artist').hashCode.abs(),
        "numsongs": 0,
      });
      albumMap[name]!["numsongs"] =
          (albumMap[name]!["numsongs"] as int) + 1;
    }
    return albumMap.values.map((m) => AlbumModel(m)).toList();
  }

  /// Fetch artists — on iOS, derive from local songs if MPMediaQuery is empty.
  static Future<List<ArtistModel>> fetchAllArtists() async {
    try {
      final artists = await OnAudioQuery().queryArtists();
      if (artists.isNotEmpty) return artists;
    } catch (_) {}

    if (!Platform.isIOS) return [];

    final songs = await _getAllSongs();
    final artistMap = <String, Map<String, dynamic>>{};
    for (final s in songs) {
      final name = (s.artist != null && s.artist!.isNotEmpty)
          ? s.artist!
          : 'Unknown Artist';
      artistMap.putIfAbsent(name, () => {
        "_id": name.hashCode.abs(),
        "artist": name,
        "number_of_albums": 0,
        "number_of_tracks": 0,
      });
      artistMap[name]!["number_of_tracks"] =
          (artistMap[name]!["number_of_tracks"] as int) + 1;
    }
    return artistMap.values.map((m) => ArtistModel(m)).toList();
  }

  /// Fetch genres — on iOS, derive from local songs if MPMediaQuery is empty.
  static Future<List<GenreModel>> fetchAllGenres() async {
    try {
      final genres = await OnAudioQuery().queryGenres();
      if (genres.isNotEmpty) return genres;
    } catch (_) {}

    if (!Platform.isIOS) return [];

    final songs = await _getAllSongs();
    final genreMap = <String, Map<String, dynamic>>{};
    for (final s in songs) {
      final name = (s.genre != null && s.genre!.isNotEmpty)
          ? s.genre!
          : 'Unknown';
      if (name == 'Unknown') continue; // skip songs without genre metadata
      genreMap.putIfAbsent(name, () => {
        "_id": name.hashCode.abs(),
        "name": name,
        "num_of_songs": 0,
      });
      genreMap[name]!["num_of_songs"] =
          (genreMap[name]!["num_of_songs"] as int) + 1;
    }
    return genreMap.values.map((m) => GenreModel(m)).toList();
  }

  /// Fetch songs for a specific artist by artist name.
  static Future<List<SongModel>> fetchSongsForArtist(int artistId) async {
    try {
      final songs = await OnAudioQuery().queryAudiosFrom(
        AudiosFromType.ARTIST_ID, artistId);
      if (songs.isNotEmpty) return songs;
    } catch (_) {}

    if (!Platform.isIOS) return [];

    final allSongs = await _getAllSongs();
    return allSongs.where((s) =>
        (s.artist?.hashCode.abs() ?? 0) == artistId ||
        s.artistId == artistId).toList();
  }

  /// Fetch songs for a specific album by album name.
  static Future<List<SongModel>> fetchSongsForAlbum(int albumId) async {
    try {
      final songs = await OnAudioQuery().queryAudiosFrom(
        AudiosFromType.ALBUM_ID, albumId);
      if (songs.isNotEmpty) return songs;
    } catch (_) {}

    if (!Platform.isIOS) return [];

    final allSongs = await _getAllSongs();
    return allSongs.where((s) =>
        (s.album?.hashCode.abs() ?? 0) == albumId ||
        s.albumId == albumId).toList();
  }

  /// Fetch songs for a specific genre.
  static Future<List<SongModel>> fetchSongsForGenre(int genreId) async {
    try {
      final songs = await OnAudioQuery().queryAudiosFrom(
        AudiosFromType.GENRE_ID, genreId);
      if (songs.isNotEmpty) return songs;
    } catch (_) {}

    if (!Platform.isIOS) return [];

    final allSongs = await _getAllSongs();
    return allSongs.where((s) =>
        (s.genre?.hashCode.abs() ?? 0) == genreId ||
        s.genreId == genreId).toList();
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
