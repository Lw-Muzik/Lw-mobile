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
import '../../models/cloud_file.dart';
import '../ytmusic/yt_models.dart';
import 'daily_mixes.dart';
import 'mix_playback.dart';
import 'mix_track_ref.dart';

/// Drive files the user has, or an empty list when no drive is linked.
typedef CloudLibrary = List<CloudFile> Function();

/// YouTube tracks that go with a taste — its genre or its artist.
///
/// Called once per mix and only for tastes the local library already has, so
/// streaming can add variety *inside* something the user likes and can never
/// invent a taste they do not.
typedef YouTubeForTaste = Future<List<YtTrack>> Function(String descriptor);

/// A mix, as far as it can be prepared without spending a request per track.
class ResolvedMix implements ResolvedMixSource {
  const ResolvedMix({
    required this.name,
    required this.descriptor,
    required this.tracks,
  });

  final String name;
  final String descriptor;
  @override
  final List<MixTrackRef> tracks;

  int get length => tracks.length;

  /// Whether anything here comes from a drive or from YouTube.
  bool get hasRemote => tracks.any((t) => t.source != MixSource.local);
}

class DailyMixService {
  DailyMixService(this._repo, {CloudLibrary? cloudLibrary, YouTubeForTaste? youTube})
      : _cloudLibrary = cloudLibrary,
        _youTube = youTube;

  final LibraryRepository _repo;
  final CloudLibrary? _cloudLibrary;
  final YouTubeForTaste? _youTube;

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
    final local = [
      for (final song in songs) _candidateOf(song, stats, hours),
    ];

    // Pass one decides the tastes, from the user's own music alone. Remote
    // tracks are then fetched for those tastes and only those — which is what
    // stops a drive full of one genre inventing a mix the library has no
    // grounds for.
    final canSupplement =
        (_cloudLibrary?.call().isNotEmpty ?? false) || _youTube != null;
    final shape = buildDailyMixes(
      library: local,
      now: moment,
      canSupplement: canSupplement,
    );
    if (shape.isEmpty) {
      _cached = const [];
      _cachedFor = stamp;
      return const [];
    }

    final remote = <MixCandidate>[];
    final refs = <String, MixTrackRef>{};
    for (final mix in shape) {
      final supplement = await _remoteFor(mix.descriptor);
      for (final entry in supplement.entries) {
        remote.add(entry.value.$1);
        refs[entry.key] = entry.value.$2;
      }
    }

    // Pass two fills those same tastes from everything available.
    final built = remote.isEmpty
        ? shape
        : buildDailyMixes(
            library: [...local, ...remote],
            now: moment,
            canSupplement: canSupplement,
          );

    final resolved = <ResolvedMix>[];
    for (final mix in built) {
      final tracks = <MixTrackRef>[
        for (final key in mix.trackKeys)
          if (byKey[key] case final song?)
            MixTrackRef.local(song)
          else if (refs[key] case final ref?)
            ref,
      ];
      // A mix whose tracks all vanished between the query and here is not worth
      // a card.
      if (tracks.isEmpty) continue;
      resolved.add(ResolvedMix(
        name: mix.name,
        descriptor: mix.descriptor,
        tracks: tracks,
      ));
    }

    _cached = resolved;
    _cachedFor = stamp;
    return resolved;
  }

  /// Drive and YouTube tracks that belong to [descriptor].
  ///
  /// Returns key -> (candidate for the engine, reference for playback).
  ///
  /// **Silent on failure.** A mix is something the app offers unasked; being
  /// offline, or signed out, or rate-limited must cost the variety and nothing
  /// else. The local mix is already correct.
  Future<Map<String, (MixCandidate, MixTrackRef)>> _remoteFor(
    String descriptor,
  ) async {
    final out = <String, (MixCandidate, MixTrackRef)>{};
    final wanted = descriptor.toLowerCase();

    final cloud = _cloudLibrary?.call() ?? const <CloudFile>[];
    for (final file in cloud) {
      final artist = file.trackArtist?.toLowerCase();
      final album = file.albumName?.toLowerCase();
      if (artist != wanted && album != wanted) continue;
      final key = 'cloud:${file.fileId}';
      out[key] = (
        MixCandidate(
          key: key,
          source: MixSource.cloud,
          artist: file.trackArtist,
          // Given the taste's own descriptor so it lands in that cluster and
          // nowhere else.
          genre: descriptor,
        ),
        MixTrackRef.cloud(file),
      );
    }

    final youTube = _youTube;
    if (youTube != null) {
      try {
        for (final track in await youTube(descriptor)) {
          final key = 'yt:${track.videoId}';
          out[key] = (
            MixCandidate(
              key: key,
              source: MixSource.youtube,
              artist: track.artist,
              genre: descriptor,
            ),
            // Marked as video only when YouTube says there is real footage;
            // MixTrackRef.youtube enforces that too.
            MixTrackRef.youtube(track, asVideo: track.hasVideo),
          );
        }
      } catch (_) {
        // See the note above: variety is the only thing lost.
      }
    }
    return out;
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
