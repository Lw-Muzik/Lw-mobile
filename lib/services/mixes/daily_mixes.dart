/// Mixes built for one person, out of the music they already own.
///
/// # What actually makes a mix feel personal
///
/// Not the recommendations — a phone has nobody to ask. Three things:
///
/// * **Clustering.** A library is not one taste, it is several. Building one
///   list out of all of them produces something that is nobody's mix. So the
///   library is split into the groups it naturally falls into and each gets its
///   own, and a group too small or too vague to be a taste gets **no mix at
///   all** rather than a thin one.
/// * **Rediscovery.** A mix of the twenty tracks someone plays most is a mix
///   they could have made themselves. Roughly two fifths of each one is music
///   they own and have barely heard.
/// * **Time.** The same mix every day is the complaint this feature exists to
///   answer. The draw is seeded with the date *and the part of the day*, so a
///   mix is stable while you are looking at it, different this evening, and
///   different again tomorrow — and once there is listening history, weighted
///   towards what this person actually reaches for at this hour.
///
/// Everything here is plain values in and plain values out: no database, no
/// clock, no random source of its own. `now` and the candidate list are
/// arguments, which is what makes "the same day gives the same mix" a testable
/// claim rather than a hope.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';

/// The parts of a day, as someone listening would describe them.
enum Daypart {
  earlyMorning('early morning', 5, 8),
  morning('morning', 8, 12),
  afternoon('afternoon', 12, 17),
  evening('evening', 17, 21),
  lateNight('late night', 21, 5);

  const Daypart(this.label, this.startHour, this.endHour);

  final String label;
  final int startHour;
  final int endHour;

  static Daypart of(DateTime time) {
    final hour = time.hour;
    for (final part in values) {
      if (part == lateNight) continue;
      if (hour >= part.startHour && hour < part.endHour) return part;
    }
    return lateNight;
  }

  /// Hours this daypart covers, for matching against listening history.
  Set<int> get hours {
    if (this == lateNight) {
      return {for (var h = 21; h < 24; h++) h, for (var h = 0; h < 5; h++) h};
    }
    return {for (var h = startHour; h < endHour; h++) h};
  }
}

/// One track, as the mix engine needs to see it.
@immutable
class MixCandidate {
  const MixCandidate({
    required this.key,
    this.artist,
    this.genre,
    this.addedAtSec,
    this.playCount = 0,
    this.plays = 0,
    this.skips = 0,
    this.hours = const {},
  });

  final String key;
  final String? artist;
  final String? genre;
  final int? addedAtSec;

  /// The library's own counter, which exists even with no event history.
  final int playCount;

  /// Plays and early abandonments drawn from the event log.
  final int plays;
  final int skips;

  /// Hours of the day this track has been played in.
  final Set<int> hours;

  /// Whether this has earned a place on its own record.
  ///
  /// Needs more than one play: skipping something once is not a verdict.
  bool get isProven {
    if (plays >= 2) return skips / plays < 0.5;
    // No event history yet — fall back to the counter a v1 install already had.
    return plays == 0 && playCount >= 2;
  }

  /// Whether this is something the user owns and has barely heard.
  bool get isNovel => plays == 0 && playCount == 0;
}

/// A finished mix.
@immutable
class DailyMix {
  const DailyMix({
    required this.name,
    required this.descriptor,
    required this.daypart,
    required this.trackKeys,
  });

  /// What the card says: "afrobeat dusk", "late night guitar".
  final String name;

  /// The cluster this was built from — a genre, or an artist when the library
  /// has no usable genres.
  final String descriptor;

  final Daypart daypart;
  final List<String> trackKeys;

  int get length => trackKeys.length;
}

/// Tuning, named so the balance can be read rather than inferred.
class MixRules {
  const MixRules._();

  /// Below this a group is not a taste, it is a handful of files. Emitting a
  /// mix for it produces a card that runs out in four minutes.
  static const minClusterSize = 8;

  /// A mix of one artist is a discography, not a mix.
  static const minDistinctArtists = 2;

  static const tracksPerMix = 25;
  static const maxMixes = 6;

  /// Share of each mix drawn from music with a listening record. The rest is
  /// rediscovery — see the note at the top of this file.
  static const provenShare = 0.6;

  /// Extra weight for a track usually played at this time of day.
  static const hourBonus = 2.0;

  /// Every candidate keeps some weight, so a mix is never the same list twice.
  static const floor = 0.5;
}

/// Builds the mixes for [now], newest-taste first.
///
/// Deterministic: the same library, the same day and the same daypart give the
/// same mixes, which is what lets a card be looked at twice without changing
/// underneath the person looking.
List<DailyMix> buildDailyMixes({
  required List<MixCandidate> library,
  required DateTime now,
  int maxMixes = MixRules.maxMixes,
  int tracksPerMix = MixRules.tracksPerMix,
}) {
  if (library.isEmpty) return const [];

  final daypart = Daypart.of(now);
  final clusters = _cluster(library);
  if (clusters.isEmpty) return const [];

  final mixes = <DailyMix>[];
  for (var i = 0; i < clusters.length && mixes.length < maxMixes; i++) {
    final cluster = clusters[i];
    final random = Random(_seedFor(now, daypart, i));
    final keys = _fill(
      cluster.tracks,
      daypart: daypart,
      limit: tracksPerMix,
      random: random,
    );
    // A cluster that cannot fill even a short mix is one the library only
    // looked like it had.
    if (keys.length < MixRules.minClusterSize) continue;
    mixes.add(DailyMix(
      name: '${cluster.descriptor.toLowerCase()} ${daypart.label}',
      descriptor: cluster.descriptor,
      daypart: daypart,
      trackKeys: keys,
    ));
  }
  return mixes;
}

/// The RNG seed for one mix.
///
/// Date and daypart and index — so the mix is stable while it is on screen,
/// different at a different time of day, and different tomorrow. Deliberately
/// not `Random()`: a mix that reshuffles every time the page rebuilds is a mix
/// nobody can point at.
int _seedFor(DateTime now, Daypart daypart, int index) {
  final day = now.year * 10000 + now.month * 100 + now.day;
  return Object.hash(day, daypart.index, index) & 0x7fffffff;
}

@immutable
class _Cluster {
  const _Cluster({required this.descriptor, required this.tracks, required this.mass});
  final String descriptor;
  final List<MixCandidate> tracks;
  final double mass;
}

/// Splits a library into the tastes it actually contains.
///
/// Genre first, because that is what a cluster *means*. Falling back to artist
/// when genres are missing or all the same is not a lesser answer for a scanned
/// library — untagged collections are common, and "everything by this artist and
/// the people near them" is still a taste.
List<_Cluster> _cluster(List<MixCandidate> library) {
  final byGenre = _group(library, (t) => t.genre);
  final usable = byGenre.where(_isTaste).toList();
  if (usable.length >= 2) return _ranked(usable);

  final byArtist = _group(library, (t) => t.artist);
  final artistClusters = byArtist.where(_isTaste).toList();
  if (artistClusters.isNotEmpty) return _ranked(artistClusters);

  // One genre or none, and no artist has enough either.
  return _ranked(usable);
}

/// A group is a taste when there is enough of it, and enough variety in it.
///
/// The artist check is what stops a single well-tagged album from becoming a
/// "mix" — twelve tracks, one artist, in order.
bool _isTaste(_Cluster cluster) {
  if (cluster.tracks.length < MixRules.minClusterSize) return false;
  final artists = <String>{};
  for (final track in cluster.tracks) {
    final artist = _normalise(track.artist);
    if (artist != null) artists.add(artist);
  }
  return artists.length >= MixRules.minDistinctArtists;
}

List<_Cluster> _ranked(List<_Cluster> clusters) {
  final sorted = [...clusters]..sort((a, b) => b.mass.compareTo(a.mass));
  return sorted;
}

List<_Cluster> _group(
  List<MixCandidate> library,
  String? Function(MixCandidate) field,
) {
  final buckets = <String, List<MixCandidate>>{};
  for (final track in library) {
    final raw = _normalise(field(track));
    if (raw == null) continue;
    (buckets[raw] ??= []).add(track);
  }
  return [
    for (final entry in buckets.entries)
      _Cluster(
        descriptor: entry.key,
        tracks: entry.value,
        // Listening mass, not size: a group of forty nobody plays is a worse
        // mix than a group of twelve somebody loves.
        mass: entry.value.fold<double>(
          0,
          (sum, t) => sum + t.playCount + t.plays * 2,
        ),
      ),
  ];
}

/// Blank and placeholder values are not a taste to cluster on.
///
/// Without this, every untagged file lands in one enormous "Unknown Artist"
/// group and the app offers a mix of everything nobody bothered to tag.
String? _normalise(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  const unknown = {'unknown', 'unknown artist', 'unknown album', '<unknown>'};
  if (unknown.contains(trimmed.toLowerCase())) return null;
  return trimmed;
}

/// Draws one mix's worth of tracks: mostly proven, substantially novel.
///
/// Both pools top each other up. A library with no listening history has an
/// empty proven pool and the whole mix comes from novelty; a library where
/// everything has been played has no novelty and the whole mix is proven.
/// Neither should produce a short mix.
List<String> _fill(
  List<MixCandidate> cluster, {
  required Daypart daypart,
  required int limit,
  required Random random,
}) {
  final proven = [for (final t in cluster) if (t.isProven) t];
  final novel = [for (final t in cluster) if (t.isNovel) t];
  // Played a little, or played and skipped — neither earned nor unheard. Kept
  // as the pool that tops the other two up.
  final rest = [
    for (final t in cluster)
      if (!t.isProven && !t.isNovel) t,
  ];

  final wantProven = (limit * MixRules.provenShare).round();
  final wantNovel = limit - wantProven;

  final picked = <String>{};
  final out = <String>[];

  void draw(List<MixCandidate> pool, int count) {
    final take = _weightedDraw(
      pool.where((t) => !picked.contains(t.key)).toList(),
      daypart: daypart,
      limit: count,
      random: random,
    );
    for (final key in take) {
      if (picked.add(key)) out.add(key);
    }
  }

  draw(proven, wantProven);
  draw(novel, wantNovel);
  // Whatever the two shares could not supply, from everything left.
  if (out.length < limit) {
    draw([...rest, ...proven, ...novel], limit - out.length);
  }
  return out;
}

/// Weighted-random without replacement, favouring what this person plays at
/// this time of day.
List<String> _weightedDraw(
  List<MixCandidate> pool, {
  required Daypart daypart,
  required int limit,
  required Random random,
}) {
  if (limit <= 0 || pool.isEmpty) return const [];

  final candidates = [...pool];
  final weights = [
    for (final track in candidates) _weight(track, daypart),
  ];

  final out = <String>[];
  var total = weights.fold<double>(0, (sum, w) => sum + w);

  while (out.length < limit && candidates.isNotEmpty) {
    var target = random.nextDouble() * total;
    var index = candidates.length - 1;
    for (var i = 0; i < candidates.length; i++) {
      target -= weights[i];
      if (target <= 0) {
        index = i;
        break;
      }
    }
    out.add(candidates.removeAt(index).key);
    total -= weights.removeAt(index);
    if (total <= 0) {
      total = weights.fold<double>(0, (sum, w) => sum + w);
      if (total <= 0) break;
    }
  }
  return out;
}

double _weight(MixCandidate track, Daypart daypart) {
  var weight = MixRules.floor;
  if (track.hours.any(daypart.hours.contains)) weight += MixRules.hourBonus;
  // A little for familiarity, capped — the difference between forty plays and
  // four hundred is not four hundred divided by forty.
  weight += min(track.playCount, 10) / 10;
  return weight;
}
