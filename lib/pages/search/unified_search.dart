/// One query, every place the user's music lives.
///
/// # Why this is a model and not more of the page
///
/// Search asks four different things at once and they answer at wildly different
/// speeds. The library is a SQLite `LIKE` and returns before the next keystroke.
/// Artists, albums, folders and playlists are one-off loads that can be cached
/// for the session. The cloud file list is already in memory. YouTube is a
/// network round-trip that may take a second, or fail, or never answer at all.
///
/// Mixing those four rhythms into `setState` inside a thousand-line widget is
/// how a search page ends up either blocking on the slowest source or rendering
/// the answer to a question the user has finished typing. Keeping the asking
/// here leaves the page free to be only a view, and makes the interesting rules
/// — supersession, silence on failure — testable without a widget tree.
///
/// # The two rules that matter
///
/// * **Local and cloud paint immediately; YouTube streams in behind them.**
///   Nothing waits on the network. A YouTube section appears with a skeleton and
///   fills when its reply lands.
/// * **A failed YouTube search is silent.** Being on a plane must not replace
///   the user's own library with an error message. It costs the YouTube section
///   and nothing else.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../data/library_repository.dart';
import '../../models/cloud_file.dart';
import '../../services/ytmusic/yt_models.dart';

/// Fetches YouTube songs for a query. Injected so the model can be tested
/// without a worker isolate and a live network.
typedef YouTubeSearch = Future<List<YtTrack>> Function(String query);

/// Loads the cached cloud file list, or an empty list when no drive is linked.
typedef CloudFileLoader = Future<List<CloudFile>> Function();

/// Loads the device's playlists. Android only; null elsewhere.
typedef PlaylistLoader = Future<List<PlaylistModel>> Function();

class UnifiedSearch extends ChangeNotifier {
  UnifiedSearch({
    required LibraryRepository repo,
    required CloudFileLoader loadCloudFiles,
    required YouTubeSearch searchYouTube,
    PlaylistLoader? loadPlaylists,
    this.debounce = const Duration(milliseconds: 250),
    bool? supportsPlaylists,
  })  : _repo = repo,
        _loadCloudFiles = loadCloudFiles,
        _searchYouTube = searchYouTube,
        _loadPlaylists = loadPlaylists,
        _supportsPlaylists = supportsPlaylists ?? Platform.isAndroid;

  final LibraryRepository _repo;
  final CloudFileLoader _loadCloudFiles;
  final YouTubeSearch _searchYouTube;
  final PlaylistLoader? _loadPlaylists;
  final bool _supportsPlaylists;

  final Duration debounce;

  Timer? _timer;

  /// Monotonic ticket for the newest query.
  ///
  /// Every asynchronous answer carries the ticket it was asked under and is
  /// discarded if that is no longer the current one. Without it a slow YouTube
  /// reply lands under a query the user has already moved past, and the section
  /// fills with results for a word that is no longer on screen.
  int _ticket = 0;

  String _query = '';
  String get query => _query;

  // --- Local library -------------------------------------------------------

  List<SongModel> _songs = const [];
  List<SongModel> get songs => _songs;

  List<ArtistModel> _artists = const [];
  List<ArtistModel> get artists => _artists;

  List<AlbumModel> _albums = const [];
  List<AlbumModel> get albums => _albums;

  List<String> _folders = const [];
  List<String> get folders => _folders;

  List<PlaylistModel> _playlists = const [];
  List<PlaylistModel> get playlists => _playlists;

  // --- Cloud ---------------------------------------------------------------

  List<CloudFile> _cloudFiles = const [];
  List<CloudFile> get cloudFiles => _cloudFiles;

  /// Every cloud file known, not just the matching ones.
  ///
  /// A station seeded from a cloud result draws from the whole drive, not from
  /// the handful of files that happened to match what was typed.
  List<CloudFile> get allCloudFiles => _allCloud ?? const [];

  // --- YouTube -------------------------------------------------------------

  List<YtTrack> _ytTracks = const [];
  List<YtTrack> get ytTracks => _ytTracks;

  bool _ytLoading = false;

  /// Whether a YouTube request is in flight for the current query.
  ///
  /// Drives a skeleton rather than a spinner: the section's shape is known
  /// before its contents are, so showing that shape is more honest than showing
  /// a circle.
  bool get ytLoading => _ytLoading;

  /// Whether the last YouTube request failed.
  ///
  /// Exposed for tests and for a quiet one-line note. Never an error dialog —
  /// see the rule at the top of this file.
  bool _ytFailed = false;
  bool get ytFailed => _ytFailed;

  // --- Session caches ------------------------------------------------------

  List<ArtistModel>? _allArtists;
  List<AlbumModel>? _allAlbums;
  List<String>? _allFolders;
  List<PlaylistModel>? _allPlaylists;
  List<CloudFile>? _allCloud;
  Future<void>? _loadingSupplemental;

  bool get hasResults =>
      _songs.isNotEmpty ||
      _artists.isNotEmpty ||
      _albums.isNotEmpty ||
      _folders.isNotEmpty ||
      _playlists.isNotEmpty ||
      _cloudFiles.isNotEmpty ||
      _ytTracks.isNotEmpty;

  /// Whether there is nothing to show and nothing still coming.
  ///
  /// Distinct from [hasResults] so the page does not flash "no results" while
  /// YouTube is still answering.
  bool get isEmptyAndSettled => !hasResults && !_ytLoading;

  /// The user typed. Debounced; the previous pending query is abandoned.
  void onQueryChanged(String value) {
    _timer?.cancel();
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      // Cancelled rather than debounced: clearing the box should empty the page
      // at once, and it costs nothing to do so.
      _ticket++;
      _query = '';
      _songs = const [];
      _artists = const [];
      _albums = const [];
      _folders = const [];
      _playlists = const [];
      _cloudFiles = const [];
      _ytTracks = const [];
      _ytLoading = false;
      _ytFailed = false;
      notifyListeners();
      return;
    }

    _timer = Timer(debounce, () => search(trimmed));
  }

  /// Runs a query now, skipping the debounce. For a submitted search.
  Future<void> search(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    final ticket = ++_ticket;
    _query = trimmed;
    // The network section is marked busy before anything is awaited, so the
    // skeleton is on screen for the whole time it is true.
    _ytLoading = true;
    _ytFailed = false;
    notifyListeners();

    await _ensureSupplemental();
    if (ticket != _ticket) return;

    // Local first and on its own, so the library is on screen while YouTube is
    // still in the air.
    final found = await _repo.searchSongs(trimmed);
    if (ticket != _ticket) return;

    _songs = found;
    _artists = _filterArtists(trimmed);
    _albums = _filterAlbums(trimmed);
    _folders = _filterFolders(trimmed);
    _playlists = _filterPlaylists(trimmed);
    _cloudFiles = _filterCloud(trimmed);
    notifyListeners();

    await _youTube(trimmed, ticket);
  }

  Future<void> _youTube(String query, int ticket) async {
    try {
      final tracks = await _searchYouTube(query);
      if (ticket != _ticket) return;
      _ytTracks = tracks;
      _ytFailed = false;
    } catch (_) {
      if (ticket != _ticket) return;
      // Silent by design. Offline is a normal state for this app, and the
      // library the user already owns is still on screen and still correct.
      _ytTracks = const [];
      _ytFailed = true;
    } finally {
      if (ticket == _ticket) {
        _ytLoading = false;
        notifyListeners();
      }
    }
  }

  /// Loads the once-per-session lists. Single-flight, so a fast typist does not
  /// start five of them.
  Future<void> _ensureSupplemental() =>
      _loadingSupplemental ??= _loadSupplemental();

  Future<void> _loadSupplemental() async {
    _allArtists = await _repo.artistsOnce();
    _allAlbums = await _repo.albumsOnce();
    if (_supportsPlaylists) {
      _allFolders = [for (final f in await _repo.foldersOnce()) f.path];
      final loader = _loadPlaylists;
      _allPlaylists = loader == null ? const [] : await loader();
    } else {
      _allFolders = const [];
      _allPlaylists = const [];
    }
    _allCloud = await _loadCloudFiles();
  }

  List<ArtistModel> _filterArtists(String q) {
    final lq = q.toLowerCase();
    return [
      for (final a in _allArtists ?? const <ArtistModel>[])
        if (a.artist.toLowerCase().contains(lq)) a,
    ];
  }

  List<AlbumModel> _filterAlbums(String q) {
    final lq = q.toLowerCase();
    return [
      for (final a in _allAlbums ?? const <AlbumModel>[])
        if (a.album.toLowerCase().contains(lq)) a,
    ];
  }

  List<String> _filterFolders(String q) {
    final lq = q.toLowerCase();
    return [
      for (final p in _allFolders ?? const <String>[])
        if (p.split('/').last.toLowerCase().contains(lq)) p,
    ];
  }

  List<PlaylistModel> _filterPlaylists(String q) {
    final lq = q.toLowerCase();
    return [
      for (final p in _allPlaylists ?? const <PlaylistModel>[])
        if (p.playlist.toLowerCase().contains(lq)) p,
    ];
  }

  List<CloudFile> _filterCloud(String q) {
    final lq = q.toLowerCase();
    return [
      for (final f in _allCloud ?? const <CloudFile>[])
        if (f.name.toLowerCase().contains(lq) ||
            (f.trackTitle?.toLowerCase().contains(lq) ?? false) ||
            (f.trackArtist?.toLowerCase().contains(lq) ?? false))
          f,
    ];
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Any reply still in the air belongs to a page that no longer exists.
    _ticket++;
    super.dispose();
  }
}

/// The real YouTube search: the songs shelf, flattened to tracks.
///
/// The songs filter rather than the unfiltered query, because unfiltered answers
/// with a shallow mixture of every kind — a couple of songs, an artist, an album
/// — and this section has room for songs.
Future<List<YtTrack>> youTubeSongs(
  Future<List<ExploreShelf>> Function(String, SearchFilter) search,
  String query,
) async {
  final shelves = await search(query, SearchFilter.songs);
  return [
    for (final shelf in shelves)
      for (final item in shelf.items)
        if (item.kind == ExploreKind.song) item.asTrack(),
  ];
}
