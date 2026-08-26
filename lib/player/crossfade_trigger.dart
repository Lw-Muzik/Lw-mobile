/// When a track is close enough to its end to start fading into the next one.
///
/// Pulled out of the position listener because the rule has grown a condition
/// that is easy to get wrong and impossible to see in a stream callback: a fade
/// must not start while a track is *being loaded*.
///
/// The race it prevents: the user presses next near the end of a track. That
/// load takes a moment — artwork, and for a streamed track a network fetch —
/// and throughout it the old track is still playing, still near its end, still
/// feeding the position listener. The listener starts a crossfade out of a
/// track the app is in the middle of replacing, so the track the user chose
/// begins and is immediately faded away into one they did not. From the outside
/// that is "I pressed next and it did something else".
library;

/// Whether the position listener should start a crossfade now.
bool shouldStartCrossfade({
  required int crossfadeSeconds,
  required bool repeatOne,
  required bool alreadyCrossfading,
  required bool loadingTrack,
  required Duration? duration,
  required Duration position,
  required int index,
  required int queueLength,
}) {
  if (crossfadeSeconds <= 0) return false;
  // Repeat-one and crossfade are contradictory instructions: the fade exists to
  // reach the *next* track, which is the one thing repeat-one says not to do.
  // The explicit setting wins.
  if (repeatOne) return false;
  if (alreadyCrossfading) return false;
  // A load in flight owns the player. See this file's header.
  if (loadingTrack) return false;
  if (duration == null) return false;
  // A track shorter than the fade has no room to fade at all.
  if (duration.inSeconds <= crossfadeSeconds) return false;
  if (position < duration - Duration(seconds: crossfadeSeconds)) return false;
  return index < queueLength - 1;
}
