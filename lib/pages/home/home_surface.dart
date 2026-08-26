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
import '../../services/mixes/daily_mix_service.dart';
import '../../services/mixes/daily_mixes.dart';
import '../../services/radio/library_station.dart';
import '../../themes/ember.dart';
import '../playlist_songs.dart';
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
    _mixService = DailyMixService(_repo);
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

  /// A mix is a running order — it was built as one — so it queues rather than
  /// seeding a station.
  void _playMix(AppController controller, ResolvedMix mix) {
    if (mix.songs.isEmpty) return;
    controller.playSongFromList(mix.songs, 0);
    Routes.playerTo(context);
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

  void _openPlaylist(PlaylistSummary playlist) {
    Routes.scaleTo(
      PlaylistSongs(
        playlistId: playlist.id,
        playlist: playlist.name,
        songs: playlist.trackCount,
      ),
      context,
    );
  }
}
