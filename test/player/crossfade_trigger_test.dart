/// When a crossfade may start — and, mostly, when it may not.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/player/crossfade_trigger.dart';

void main() {
  bool trigger({
    int crossfadeSeconds = 20,
    bool repeatOne = false,
    bool alreadyCrossfading = false,
    bool loadingTrack = false,
    Duration? duration = const Duration(seconds: 180),
    Duration position = const Duration(seconds: 165),
    int index = 0,
    int queueLength = 10,
  }) =>
      shouldStartCrossfade(
        crossfadeSeconds: crossfadeSeconds,
        repeatOne: repeatOne,
        alreadyCrossfading: alreadyCrossfading,
        loadingTrack: loadingTrack,
        duration: duration,
        position: position,
        index: index,
        queueLength: queueLength,
      );

  test('starts once the track is inside the fade window', () {
    expect(trigger(), isTrue);
  });

  test('not before the window', () {
    expect(trigger(position: const Duration(seconds: 159)), isFalse);
  });

  /// The bug this predicate exists for. Press next near the end of a track and
  /// the load takes a moment; the outgoing track is still playing and still
  /// inside its fade window the whole time. Without this the listener starts a
  /// fade out of the track being replaced, so the track the user asked for
  /// begins and is immediately faded away into one they did not choose.
  test('never while a track is being loaded', () {
    expect(trigger(loadingTrack: true), isFalse);
  });

  test('never twice at once', () {
    expect(trigger(alreadyCrossfading: true), isFalse);
  });

  test('never under repeat-one, which says not to reach the next track', () {
    expect(trigger(repeatOne: true), isFalse);
  });

  test('never when crossfade is switched off', () {
    expect(trigger(crossfadeSeconds: 0), isFalse);
  });

  test('never on a track with no known duration', () {
    expect(trigger(duration: null), isFalse);
  });

  test('never on a track shorter than the fade itself', () {
    expect(
      trigger(
        duration: const Duration(seconds: 15),
        position: const Duration(seconds: 14),
      ),
      isFalse,
    );
  });

  test('never on the last track — there is nothing to fade into', () {
    expect(trigger(index: 9, queueLength: 10), isFalse);
  });
}
