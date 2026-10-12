/// Putting a queue in and out of shuffled order.
///
/// # Why this is not a method on the controller
///
/// It used to be, and the arithmetic was wrong in a way that only showed up
/// when a track ended. The shuffled list, the original list and the playing
/// index were read through a getter that silently switched which list it
/// returned depending on a flag the *caller* had already flipped — so
/// unshuffling looked up the playing track in the wrong list and restored the
/// user to something they had never chosen.
///
/// Pure functions over explicit lists cannot make that mistake: there is no
/// ambient flag to be out of step with, and every case that used to be
/// unreachable in a debugger is one line in a test.
///
/// # Identity is the song id
///
/// The same track appears as different `SongModel` objects in the two lists —
/// they are built separately from the same media-store row. Comparing by
/// reference finds nothing, and "found nothing" was previously indistinguishable
/// from "found it at position 0".
library;

import 'dart:math';

import 'package:on_audio_query/on_audio_query.dart';

class QueueOrder {
  const QueueOrder._();

  /// A shuffled copy of [source] with [current] moved to the front.
  ///
  /// The playing track leads so that turning shuffle on does not interrupt it:
  /// the queue is reordered *around* what the user is listening to, not
  /// including it. A [current] that is not in [source] is ignored rather than
  /// inserted — a stale reference must not grow the queue by one.
  ///
  /// [seed] exists for tests. Production callers omit it and get a fresh
  /// [Random] each time, because a shuffle that is the same every launch is not
  /// one.
  static List<SongModel> shuffle(
    List<SongModel> source,
    SongModel? current, {
    int? seed,
  }) {
    final shuffled = List<SongModel>.of(source)..shuffle(Random(seed));
    if (current == null) return shuffled;

    final at = shuffled.indexWhere((song) => song.id == current.id);
    if (at <= 0) return shuffled;
    shuffled
      ..removeAt(at)
      ..insert(0, current);
    return shuffled;
  }

  /// Where [song] sits in [list].
  ///
  /// Returns 0 rather than -1 when it is not there. The result is used to
  /// subscript the queue, and a queue that has changed underneath a stale
  /// reference should start from the top, never crash.
  static int indexOf(List<SongModel> list, SongModel? song) {
    if (song == null) return 0;
    final at = list.indexWhere((candidate) => candidate.id == song.id);
    return at < 0 ? 0 : at;
  }

  /// Both orderings of a queue with [extra] placed right after the playing
  /// track, or null when nothing follows it (the caller appends instead).
  ///
  /// [playingIndex] is a position in the list the user is looking at —
  /// [shuffled] while [isShuffled], otherwise [original]. The extras go in
  /// straight after the playing track there. In the *other* ordering they go
  /// after that same song, found by id, so that switching shuffle off keeps
  /// them beside the song they were queued behind rather than stranding them
  /// at a position that only meant something in the shuffled order. If the
  /// playing song is somehow not in the other list, they go on its end.
  static ({List<SongModel> original, List<SongModel> shuffled})? insertNext({
    required List<SongModel> original,
    required List<SongModel> shuffled,
    required bool isShuffled,
    required int playingIndex,
    required List<SongModel> extra,
  }) {
    final visible = isShuffled ? shuffled : original;
    if (playingIndex < 0 || playingIndex >= visible.length - 1) return null;

    final playing = visible[playingIndex];
    final nextOriginal = List<SongModel>.of(original);
    final nextShuffled = List<SongModel>.of(shuffled);
    final into = isShuffled ? nextShuffled : nextOriginal;
    final other = isShuffled ? nextOriginal : nextShuffled;

    into.insertAll(playingIndex + 1, extra);
    final at = other.indexWhere((song) => song.id == playing.id);
    other.insertAll(at < 0 ? other.length : at + 1, extra);
    return (original: nextOriginal, shuffled: nextShuffled);
  }
}
