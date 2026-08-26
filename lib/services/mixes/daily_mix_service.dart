/// Turning the library database into mixes that can be played.
///
/// The arithmetic lives in `daily_mixes.dart` and knows nothing about SQLite,
/// artwork or `SongModel`. This is the layer that feeds it: it reads the
/// library and its listening history, hands both to the engine, and maps the
/// keys that come back to the tracks the player takes.
///
/// Mixes are cached for the daypart they were built in. Rebuilding on every
/// rebuild of a widget would be three queries and a clustering pass to produce
/// — by design — exactly the same answer.
library;

import 'package:on_audio_query/on_audio_query.dart';

import '../../data/library_repository.dart';
import 'daily_mixes.dart';

/// A mix with its tracks resolved, ready to hand to the player.
class ResolvedMix {
  const ResolvedMix({
    required this.name,
    required this.descriptor,
    required this.songs,
  });

  final String name;
  final String descriptor;
  final List<SongModel> songs;

  int get length => songs.length;
}

class DailyMixService {
  DailyMixService(this._repo);

  final LibraryRepository _repo;

  List<ResolvedMix>? _cached;
  String? _cachedFor;

  /// A stamp that changes exactly when the mixes should.
  static String stampFor(DateTime now) =>
      '${now.year}-${now.month}-${now.day}-${Daypart.of(now).index}';

  /// The mixes for [now], built once per daypart.
  ///
  /// [force] rebuilds regardless — for a pull-to-refresh, where the user has
  /// asked for something new and getting the same list back would read as the
  /// gesture having failed.
  Future<List<ResolvedMix>> mixes({DateTime? now, bool force = false}) async {
    final moment = now ?? DateTime.now();
    final stamp = stampFor(moment);
    final cached = _cached;
    if (!force && cached != null && _cachedFor == stamp) return cached;

    final songs = await _repo.allSongs();
    if (songs.isEmpty) {
      _cached = const [];
      _cachedFor = stamp;
      return const [];
    }

    // Two small aggregate queries rather than one per track.
    final stats = await _repo.playStats();
    final hours = await _repo.playHours();

    final byKey = {for (final song in songs) song.id.toString(): song};
    final candidates = [
      for (final song in songs) _candidateOf(song, stats, hours),
    ];

    final built = buildDailyMixes(library: candidates, now: moment);
    final resolved = <ResolvedMix>[];
    for (final mix in built) {
      final tracks = [
        for (final key in mix.trackKeys)
          if (byKey[key] case final song?) song,
      ];
      // A mix whose tracks all vanished between the query and here is not worth
      // a card.
      if (tracks.isEmpty) continue;
      resolved.add(ResolvedMix(
        name: mix.name,
        descriptor: mix.descriptor,
        songs: tracks,
      ));
    }

    _cached = resolved;
    _cachedFor = stamp;
    return resolved;
  }

  /// Drops the cache. For after a library scan, which can change what tastes
  /// the library even contains.
  void invalidate() {
    _cached = null;
    _cachedFor = null;
  }

  static MixCandidate _candidateOf(
    SongModel song,
    Map<int, PlayStats> stats,
    Map<int, Set<int>> hours,
  ) {
    final map = song.getMap;
    final stat = stats[song.id];
    return MixCandidate(
      key: song.id.toString(),
      artist: song.artist,
      genre: map['genre'] as String?,
      addedAtSec: (map['date_added'] as num?)?.toInt(),
      playCount: (map['play_count'] as num?)?.toInt() ?? 0,
      plays: stat?.plays ?? 0,
      skips: stat?.skips ?? 0,
      hours: hours[song.id] ?? const {},
    );
  }
}
