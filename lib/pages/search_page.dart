import 'dart:async';
import 'dart:io';

import '/exports/exports.dart';
import '/Routes/routes.dart';

import '../controllers/AppController.dart';
import '../data/library_repository.dart';
import '../models/cloud_file.dart';
import '../player/player_ui.dart';
import '../widgets/ArtworkWidget.dart';
import '../widgets/song_tile.dart';
import 'album_songs.dart';
import 'artist_songs.dart';
import 'folder_songs.dart';
import 'playlist_songs.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  String _query = '';

  // Lazy-loaded data sources (cached after first load)
  List<ArtistModel>? _allArtists;
  List<AlbumModel>? _allAlbums;
  List<String>? _allFolders;
  List<PlaylistModel>? _allPlaylists;
  List<CloudFile>? _allCloudFiles;
  bool _dataLoading = false;

  // Song search + discovery now read the library DB, not the playback queue.
  List<SongModel> _songResults = [];
  List<SongModel> _mostPlayed = [];
  List<SongModel> _recentlyAdded = [];

  LibraryRepository get _repo => context.read<LibraryRepository>();

  @override
  void initState() {
    super.initState();
    // Auto-focus the search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    _loadDiscovery();
  }

  Future<void> _loadDiscovery() async {
    final most = await _repo.mostPlayed(limit: 10);
    final recent = await _repo.recentlyAdded(limit: 10);
    if (!mounted) return;
    setState(() {
      _mostPlayed = most;
      _recentlyAdded = recent;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      final q = value.trim();
      // Song results come straight from a DB LIKE query — the whole library,
      // not just the last-played queue.
      final results = q.isEmpty ? <SongModel>[] : await _repo.searchSongs(q);
      if (!mounted) return;
      setState(() {
        _query = q;
        _songResults = results;
      });
      // Lazy-load supplemental data (artists/albums/folders) on first real query
      if (_query.isNotEmpty && !_dataLoading && _allArtists == null) {
        _loadSupplementalData();
      }
    });
  }

  Future<void> _loadSupplementalData() async {
    _dataLoading = true;
    final artists = await _repo.artistsOnce();
    final albums = await _repo.albumsOnce();
    final folders = Platform.isAndroid ? await _repo.foldersOnce() : null;
    final playlists = Platform.isAndroid
        ? await OnAudioQuery().queryPlaylists()
        : null;

    if (!mounted) return;

    _allArtists = artists;
    _allAlbums = albums;
    if (Platform.isAndroid) {
      _allFolders = folders!.map((f) => f.path).toList();
      _allPlaylists = playlists;
    }

    // Load cloud files from cache
    final controller = context.read<AppController>();
    _allCloudFiles = _loadCachedCloudFiles(controller);

    _dataLoading = false;
    if (mounted) setState(() {});
  }

  List<CloudFile> _loadCachedCloudFiles(AppController controller) {
    final files = <CloudFile>[];
    final gdriveList =
        controller.cloudCache.loadFileList(CloudProvider.googleDrive);
    if (gdriveList != null) files.addAll(gdriveList);
    final dropboxList =
        controller.cloudCache.loadFileList(CloudProvider.dropbox);
    if (dropboxList != null) files.addAll(dropboxList);
    return files;
  }

  // ---------------------------------------------------------------------------
  // Filtering
  // ---------------------------------------------------------------------------

  List<ArtistModel> _filterArtists() {
    if (_allArtists == null) return [];
    final lq = _query.toLowerCase();
    return _allArtists!
        .where((a) => (a.artist).toLowerCase().contains(lq))
        .toList();
  }

  List<AlbumModel> _filterAlbums() {
    if (_allAlbums == null) return [];
    final lq = _query.toLowerCase();
    return _allAlbums!
        .where((a) => (a.album).toLowerCase().contains(lq))
        .toList();
  }

  List<String> _filterFolders() {
    if (_allFolders == null) return [];
    final lq = _query.toLowerCase();
    return _allFolders!
        .where((p) => p.split('/').last.toLowerCase().contains(lq))
        .toList();
  }

  List<PlaylistModel> _filterPlaylists() {
    if (_allPlaylists == null) return [];
    final lq = _query.toLowerCase();
    return _allPlaylists!
        .where((p) => (p.playlist).toLowerCase().contains(lq))
        .toList();
  }

  List<CloudFile> _filterCloud() {
    if (_allCloudFiles == null || _allCloudFiles!.isEmpty) return [];
    final lq = _query.toLowerCase();
    return _allCloudFiles!.where((f) {
      return f.name.toLowerCase().contains(lq) ||
          (f.trackTitle?.toLowerCase().contains(lq) ?? false) ||
          (f.trackArtist?.toLowerCase().contains(lq) ?? false);
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Routes.pop(context),
        ),
        titleSpacing: 0,
        title: TextField(
          controller: _searchController,
          focusNode: _focusNode,
          onChanged: _onQueryChanged,
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: 'Songs, artists, albums...',
            hintStyle: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          ),
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () {
                _searchController.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: Consumer<AppController>(
        builder: (context, controller, _) {
          if (_query.isEmpty) {
            return _buildDiscoveryView(controller, theme, colorScheme);
          }
          return _buildSearchResults(controller, theme, colorScheme);
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty query — discovery view (Most Played + Recently Added)
  // ---------------------------------------------------------------------------

  Widget _buildDiscoveryView(
    AppController controller,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final mostPlayed = _mostPlayed;
    final recentlyAdded = _recentlyAdded;

    if (mostPlayed.isEmpty && recentlyAdded.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_rounded,
              size: 72,
              color: colorScheme.onSurface.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 16),
            Text(
              'Search your library',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Find songs, artists, albums, and more',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      children: [
        if (mostPlayed.isNotEmpty) ...[
          _buildSectionHeader('Most Played', theme, colorScheme),
          const SizedBox(height: 8),
          _buildHorizontalSongCards(
            mostPlayed,
            controller,
            theme,
            colorScheme,
            showPlayCount: true,
          ),
          const SizedBox(height: 24),
        ],
        if (recentlyAdded.isNotEmpty) ...[
          _buildSectionHeader('Recently Added', theme, colorScheme),
          const SizedBox(height: 8),
          _buildHorizontalSongCards(
            recentlyAdded,
            controller,
            theme,
            colorScheme,
          ),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(
    String title,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  Widget _buildHorizontalSongCards(
    List<SongModel> songs,
    AppController controller,
    ThemeData theme,
    ColorScheme colorScheme, {
    bool showPlayCount = false,
  }) {
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          final playCount = controller.getPlayCount(song.id);
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => _playSong(controller, songs, song),
              child: SizedBox(
                width: 130,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Artwork card with optional play count badge
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ArtworkWidget(
                            songId: song.id,
                            type: ArtworkType.AUDIO,
                            width: 130,
                            height: 130,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        if (showPlayCount && playCount > 0)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: colorScheme.primary
                                    .withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.play_arrow_rounded,
                                      size: 12, color: colorScheme.onPrimary),
                                  const SizedBox(width: 2),
                                  Text(
                                    '$playCount',
                                    style: TextStyle(
                                      color: colorScheme.onPrimary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Title
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    // Artist
                    Text(
                      song.artist ?? 'Unknown',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Search results view
  // ---------------------------------------------------------------------------

  Widget _buildSearchResults(
    AppController controller,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final songs = _songResults;
    final artists = _filterArtists();
    final albums = _filterAlbums();
    final folders = _filterFolders();
    final playlists = _filterPlaylists();
    final cloudFiles = _filterCloud();

    final hasResults = songs.isNotEmpty ||
        artists.isNotEmpty ||
        albums.isNotEmpty ||
        folders.isNotEmpty ||
        playlists.isNotEmpty ||
        cloudFiles.isNotEmpty;

    if (!hasResults) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: colorScheme.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 12),
            Text(
              'No results for "$_query"',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 100),
      children: [
        // Songs section
        if (songs.isNotEmpty)
          _buildSongsSection(songs, controller, theme, colorScheme),

        // Artists section
        if (artists.isNotEmpty)
          _buildArtistsSection(artists, theme, colorScheme),

        // Albums section
        if (albums.isNotEmpty)
          _buildAlbumsSection(albums, theme, colorScheme),

        // Folders section (Android only)
        if (folders.isNotEmpty)
          _buildFoldersSection(folders, theme, colorScheme),

        // Playlists section
        if (playlists.isNotEmpty)
          _buildPlaylistsSection(playlists, theme, colorScheme),

        // Cloud section
        if (cloudFiles.isNotEmpty)
          _buildCloudSection(cloudFiles, theme, colorScheme),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Songs section
  // ---------------------------------------------------------------------------

  Widget _buildSongsSection(
    List<SongModel> songs,
    AppController controller,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final displaySongs = songs.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildResultSectionHeader(
          'Songs',
          Icons.music_note_rounded,
          '${songs.length}',
          theme,
          colorScheme,
        ),
        ...displaySongs.map((song) {
          final isPlaying =
              controller.songs.isNotEmpty &&
              controller.songId >= 0 &&
              controller.songId < controller.songs.length &&
              controller.songs[controller.songId].id == song.id;
          return SongTile(
            song: song,
            index: displaySongs.indexOf(song),
            isCurrentTrack: isPlaying,
            showTrackNumber: false,
            showOptionsIcon: false,
            onTap: () => _playSong(controller, songs, song),
          );
        }),
        if (songs.length > 5)
          _buildSeeAllButton(
            'See all ${songs.length} songs',
            theme,
            colorScheme,
            onTap: () => _showAllSongs(songs, controller),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Artists section
  // ---------------------------------------------------------------------------

  Widget _buildArtistsSection(
    List<ArtistModel> artists,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildResultSectionHeader(
          'Artists',
          Icons.person_rounded,
          '${artists.length}',
          theme,
          colorScheme,
        ),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: artists.take(10).length,
            itemBuilder: (context, index) {
              final artist = artists[index];
              final name = artist.artist;
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => _navigateToArtist(artist),
                  child: SizedBox(
                    width: 72,
                    child: Column(
                      children: [
                        ClipOval(
                          child: ArtworkWidget(
                            songId: artist.id,
                            type: ArtworkType.ARTIST,
                            width: 60,
                            height: 60,
                            borderRadius: BorderRadius.zero,
                            other: name,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          name,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Albums section
  // ---------------------------------------------------------------------------

  Widget _buildAlbumsSection(
    List<AlbumModel> albums,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildResultSectionHeader(
          'Albums',
          Icons.album_rounded,
          '${albums.length}',
          theme,
          colorScheme,
        ),
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: albums.take(10).length,
            itemBuilder: (context, index) {
              final album = albums[index];
              final name = album.album;
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => _navigateToAlbum(album),
                  child: SizedBox(
                    width: 110,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: ArtworkWidget(
                            songId: album.id,
                            type: ArtworkType.ALBUM,
                            width: 110,
                            height: 110,
                            borderRadius: BorderRadius.circular(10),
                            other: name,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Folders section
  // ---------------------------------------------------------------------------

  Widget _buildFoldersSection(
    List<String> folders,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final display = folders.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildResultSectionHeader(
          'Folders',
          Icons.folder_rounded,
          '${folders.length}',
          theme,
          colorScheme,
        ),
        ...display.map((path) {
          final name = path.split('/').last;
          return ListTile(
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
            leading: Icon(
              Icons.folder_rounded,
              color: colorScheme.primary.withValues(alpha: 0.7),
              size: 28,
            ),
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
            onTap: () => _navigateToFolder(path),
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Playlists section
  // ---------------------------------------------------------------------------

  Widget _buildPlaylistsSection(
    List<PlaylistModel> playlists,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final display = playlists.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildResultSectionHeader(
          'Playlists',
          Icons.queue_music_rounded,
          '${playlists.length}',
          theme,
          colorScheme,
        ),
        ...display.map((playlist) {
          return ListTile(
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
            leading: Icon(
              Icons.queue_music_rounded,
              color: colorScheme.tertiary.withValues(alpha: 0.7),
              size: 28,
            ),
            title: Text(
              playlist.playlist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              '${playlist.numOfSongs} songs',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
            onTap: () => _navigateToPlaylist(playlist),
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Cloud section
  // ---------------------------------------------------------------------------

  Widget _buildCloudSection(
    List<CloudFile> cloudFiles,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final display = cloudFiles.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildResultSectionHeader(
          'Cloud',
          Icons.cloud_rounded,
          '${cloudFiles.length}',
          theme,
          colorScheme,
        ),
        ...display.map((file) {
          final icon = file.provider == CloudProvider.googleDrive
              ? Icons.drive_file_move_rounded
              : Icons.cloud_circle_rounded;
          final providerName = file.provider == CloudProvider.googleDrive
              ? 'Google Drive'
              : 'Dropbox';
          return ListTile(
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
            leading: Icon(
              icon,
              color: colorScheme.secondary.withValues(alpha: 0.7),
              size: 28,
            ),
            title: Text(
              file.trackTitle ?? file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              '${file.trackArtist ?? file.folderName} · $providerName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Shared widgets
  // ---------------------------------------------------------------------------

  Widget _buildResultSectionHeader(
    String title,
    IconData icon,
    String count,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              count,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeeAllButton(
    String label,
    ThemeData theme,
    ColorScheme colorScheme, {
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Navigation / Actions
  // ---------------------------------------------------------------------------

  void _playSong(
      AppController controller, List<SongModel> list, SongModel song) {
    var index = list.indexWhere((s) => s.id == song.id);
    // Play from the surfaced list (search results / discovery row). Falls back
    // to a single-track queue so a tap ALWAYS plays — the old code searched the
    // last-played queue and silently did nothing when the song wasn't in it.
    List<SongModel> queue = list;
    if (index == -1) {
      queue = [song];
      index = 0;
    }
    controller.playSongFromList(queue, index);
    Routes.routeTo(const Player(), context);
  }

  void _showAllSongs(List<SongModel> songs, AppController controller) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text('Songs matching "$_query"'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: SongListView(
            songs: songs,
            controller: controller,
            showTrackNumbers: false,
            showOptionsIcon: false,
            onTap: (song, index) {
              controller.playSongFromList(songs, index);
              Routes.routeTo(const Player(), context);
            },
          ),
        ),
      ),
    );
  }

  void _navigateToArtist(ArtistModel artist) {
    final artistName = artist.artist;
    Routes.scaleTo(
      ArtistSongs(
        songs: artist.numberOfTracks ?? 0,
        albums: artist.numberOfAlbums ?? 0,
        artistId: artist.id,
        artist: artistName,
      ),
      context,
    );
  }

  void _navigateToAlbum(AlbumModel album) {
    final albumName = album.album;
    Routes.scaleTo(
      AlbumSongs(
        albumId: album.id,
        album: albumName,
        songs: album.numOfSongs,
      ),
      context,
    );
  }

  void _navigateToFolder(String path) {
    Routes.scaleTo(FolderSongs(path: path), context);
  }

  void _navigateToPlaylist(PlaylistModel playlist) {
    Routes.scaleTo(
      PlaylistSongs(
        playlistId: playlist.id,
        playlist: playlist.playlist,
        songs: playlist.numOfSongs,
      ),
      context,
    );
  }
}
