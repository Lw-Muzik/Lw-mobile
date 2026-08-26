/// The landing surface: what this person should hear right now.
///
/// # Every shelf can be absent
///
/// A new install has no listening history, may have no playlists, and may have
/// nothing to jump back into. Each shelf here renders **nothing at all** when it
/// has nothing — not a placeholder, not "no recent tracks yet". A first run is
/// then a short page rather than a page full of apologies, and it grows into
/// itself as the library gets used.
///
/// # Nothing here waits on the network
///
/// Mixes, playlists, recents and rediscovery all come from the local database.
/// The page is complete and useful with the phone in aeroplane mode.
library;

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../../controllers/app_controller.dart';
import '../../data/library_repository.dart';
import '../../routes/routes.dart';
import '../../models/cloud_file.dart';
import '../../services/mixes/daily_mix_service.dart';
import '../../services/mixes/daily_mixes.dart';
import '../../services/mixes/mix_playback.dart';
import '../../services/ytmusic/yt_models.dart';
import '../../services/ytmusic/yt_repository.dart';
import '../../services/radio/library_station.dart';
import '../../themes/ember.dart';
import 'mix_playlist_page.dart';
import 'widgets/shelf.dart';

class HomeSurface extends StatefulWidget {
  const HomeSurface({super.key});

  @override
  State<HomeSurface> createState() => _HomeSurfaceState();
}

class _HomeSurfaceState extends State<HomeSurface> {
  DailyMixService? _mixService;

  List<ResolvedMix> _mixes = const [];
  List<SongModel> _recent = const [];
  List<SongModel> _rediscover = const [];
  List<PlaylistSummary> _playlists = const [];
  bool _loaded = false;

  LibraryRepository get _repo => context.read<LibraryRepository>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Guarded: didChangeDependencies runs again on any inherited-widget change.
    if (_mixService != null) return;
    final controller = context.read<AppController>();
    _mixService = DailyMixService(
      _repo,
      // A drive the user has linked; empty when they have not.
      cloudLibrary: () {
        final files = <CloudFile>[];
        for (final provider in CloudProvider.values) {
          final list = controller.cloudCache.loadFileList(provider);
          if (list != null) files.addAll(list);
        }
        return files;
      },
      // Songs that go with a taste the library already has. Fails silently —
      // offline costs the variety and nothing else.
      youTube: (descriptor) async {
        // Songs and music videos both. A mix of one artist's catalogue is
        // better for having the video of the single in it, and the Videos tab
        // is otherwise the only place footage ever appears.
        final results = await Future.wait([
          YtMusicRepository.instance.search(descriptor, SearchFilter.songs),
          YtMusicRepository.instance.search(descriptor, SearchFilter.videos),
        ]);
        return [
          for (final shelf in results.first)
            for (final item in shelf.items)
              if (item.kind == ExploreKind.song) item.asTrack(),
          for (final shelf in results.last)
            for (final item in shelf.items)
              if (item.kind == ExploreKind.video) item.asTrack(),
        ];
      },
    );
    _load();
  }

  Future<void> _load({bool force = false}) async {
    final mixes = await _mixService!.mixes(force: force);
    final recent = await _repo.mostPlayed(limit: 12);
    final rediscover = await _repo.rediscover(limit: 12);
    final playlists = await _repo.playlists();
    if (!mounted) return;
    setState(() {
      _mixes = mixes;
      _recent = recent;
      _rediscover = rediscover;
      _playlists = playlists;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final daypart = Daypart.of(DateTime.now());

    final shelves = <Widget>[
      _greeting(daypart),
      if (_mixes.isNotEmpty)
        MixShelf(
          title: 'MADE FOR YOU',
          mixes: _mixes,
          onTap: (mix) => _playMix(controller, mix),
          onSave: _saveMixAsPlaylist,
        ),
      if (_playlists.isNotEmpty)
        PlaylistShelf(
          title: 'YOUR PLAYLISTS',
          playlists: _playlists,
          onTap: _openPlaylist,
        ),
      if (_recent.isNotEmpty)
        SongShelf(
          title: 'JUMP BACK IN',
          songs: _recent,
          onTap: (song, list) => _play(controller, list, song),
        ),
      if (_rediscover.isNotEmpty)
        SongShelf(
          title: 'REDISCOVER',
          subtitle: 'Yours, and barely played',
          songs: _rediscover,
          onTap: (song, list) => _play(controller, list, song),
        ),
    ];

    // Only the greeting: the library is empty or still scanning. Say so once,
    // rather than stacking four empty shelves.
    final isBare = shelves.length == 1;

    return RefreshIndicator(
      color: Ember.ember400,
      backgroundColor: Ember.surface,
      onRefresh: () => _load(force: true),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ...shelves,
          if (isBare && _loaded) _emptyLibrary(),
        ],
      ),
    );
  }

  Widget _greeting(Daypart daypart) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Ember.gutter, 8, Ember.gutter, Ember.shelfGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Good ${_greetingWord(daypart)}',
            style: const TextStyle(
              color: Ember.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            daypart.label,
            style: TextStyle(color: Ember.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  static String _greetingWord(Daypart daypart) => switch (daypart) {
        Daypart.earlyMorning || Daypart.morning => 'morning',
        Daypart.afternoon => 'afternoon',
        Daypart.evening => 'evening',
        Daypart.lateNight => 'evening',
      };

  Widget _emptyLibrary() {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Ember.gutter, vertical: 48),
      child: Column(
        children: [
          Icon(Icons.library_music_outlined,
              size: 56, color: Ember.textTertiary),
          const SizedBox(height: 16),
          Text(
            'Nothing here yet',
            style: TextStyle(
              color: Ember.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Mixes appear once there is music to build them from.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Ember.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------

  /// A mix may hold drive and YouTube tracks that are not playable yet, so this
  /// starts on the first one that resolves and grows behind it.
  Future<void> _playMix(AppController controller, ResolvedMix mix) async {
    if (mix.tracks.isEmpty) return;
    Routes.playerTo(context);
    await MixPlayback.play(
      controller,
      mix,
      resolveCloud: (file) async {
        if (file.provider == CloudProvider.googleDrive) {
          return controller.googleDriveService.getStreamUrl(file.fileId);
        }
        return controller.dropboxService.getTemporaryLink(file.fileId);
      },
    );
  }

  /// A shelf is a report, not a running order, so tapping one seeds a station —
  /// the same rule search follows.
  Future<void> _play(
    AppController controller,
    List<SongModel> list,
    SongModel song,
  ) async {
    Routes.playerTo(context);
    await controller.playStation(
      song,
      LibraryStation(repo: _repo, seed: song),
    );
  }

  /// Opens an **app-owned** playlist.
  ///
  /// Deliberately not `PlaylistSongs`, which reads MediaStore: these rows can
  /// hold a drive file and a YouTube track, and their ids mean nothing there.
  void _openPlaylist(PlaylistSummary playlist) {
    Routes.scaleTo(MixPlaylistPage(playlist: playlist), context);
  }

  /// Keeps a mix, exactly as it stands, as a playlist.
  ///
  /// A mix is rebuilt tomorrow by design — which is the point of it, and also
  /// why there has to be a way to say "not this one, I want to keep it". The
  /// entries carry their source, so a saved mix keeps its drive and YouTube
  /// tracks rather than collapsing to the local ones.
  Future<void> _saveMixAsPlaylist(ResolvedMix mix) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final id = await _repo.createPlaylist(mix.name, now);
    await _repo.addToPlaylist(
      id,
      [
        for (final ref in mix.tracks)
          PlaylistItem(
            source: switch (ref.source) {
              MixSource.cloud => 'cloud',
              MixSource.youtube => 'youtube',
              MixSource.local => 'local',
            },
            songId: ref.song?.id,
            externalId: ref.file?.fileId ?? ref.track?.videoId,
            title: ref.title,
            artist: ref.artist,
          ),
      ],
      now,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved "${mix.name}" to your playlists')),
    );
    await _load();
  }
}
