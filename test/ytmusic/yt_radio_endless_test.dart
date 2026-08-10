/// Why a station that stopped at 26 tracks was never a network problem.
///
/// Two separate faults produced the same symptom, and the live test proves it
/// was neither of the ones you would suspect: against the real service page one
/// carries 49 tracks and a continuation token, and page two carries 23 the
/// first did not. The fetching was fine all along.
///
///   1. Nothing asked. The top-up was wired to the two branches of the
///      natural-end handler only, so skipping by hand never asked for more, and
///      neither did a crossfade — which advances the index itself and so never
///      reaches that handler at all. One page, then silence.
///
///   2. Nothing left to ask for. A single seed converges: 49 new, then 25, 13,
///      4, 3 — roughly 94 tracks before every page is repeats. Endless has to
///      survive that, and survive it with related music rather than a shuffle.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/services/ytmusic/yt_models.dart';
import 'package:eq_app/services/ytmusic/yt_playback.dart';

YtTrack track(String id) => YtTrack(videoId: id, title: 'Track $id');

void main() {
  final radio = YtRadioQueue.instance;

  setUp(radio.resetForTest);

  group('when the queue is short enough to top up', () {
    test('a queue with plenty left is left alone', () {
      expect(YtRadioQueue.needsFill(queueLength: 50, index: 0), isFalse);
      expect(YtRadioQueue.needsFill(queueLength: 50, index: 20), isFalse);
    });

    test('five tracks from the end is the moment to fetch', () {
      // 26 tracks, playing the 21st: five to go.
      expect(YtRadioQueue.needsFill(queueLength: 26, index: 20), isTrue);
      expect(YtRadioQueue.needsFill(queueLength: 26, index: 19), isFalse);
    });

    test('the last track certainly needs more', () {
      expect(YtRadioQueue.needsFill(queueLength: 26, index: 25), isTrue);
    });

    test('an index past the end still asks rather than going quiet', () {
      // A queue that shrank under a running station must not leave the fetch
      // permanently unreachable.
      expect(YtRadioQueue.needsFill(queueLength: 3, index: 9), isTrue);
    });
  });

  group('re-seeding keeps the station going', () {
    test('moves the seed to the deepest track the station chose', () {
      radio.attach(seed: 'seed');
      radio.offerForTest(['a', 'b', 'c']);

      expect(radio.reseedForTest(), isTrue);
      expect(radio.seedForTest, 'c',
          reason: 'the furthest the station got is the direction it was going');
    });

    test('the new seed is a track this station picked, never an arbitrary one',
        () {
      radio.attach(seed: 'seed');
      radio.offerForTest(['related']);
      radio.reseedForTest();

      // 'related' was returned by the station as a match for 'seed', so asking
      // what matches 'related' walks through neighbouring music. That is the
      // whole difference between an endless station and a shuffle.
      expect(radio.seedForTest, 'related');
    });

    test('nothing already heard comes back after a re-seed', () {
      radio.attach(seed: 'seed');
      radio.offerForTest(['a', 'b']);
      radio.reseedForTest();

      final fresh = radio.freshTracksForTest(
        [track('a'), track('b'), track('new')],
        limit: 10,
      );
      expect([for (final t in fresh) t.videoId], ['new'],
          reason: 're-seeding must not reset what the station already played');
    });

    test('a station with nothing offered yet has nowhere to move to', () {
      radio.attach(seed: 'seed');
      expect(radio.reseedForTest(), isFalse);
      expect(radio.seedForTest, 'seed');
    });

    test('will not re-seed onto the seed it is already using', () {
      radio.attach(seed: 'seed');
      radio.offerForTest(['a']);
      expect(radio.reseedForTest(), isTrue);
      expect(radio.seedForTest, 'a');
      // Nothing new has been offered since, so there is nowhere further to go
      // and asking the same seed again would only repeat the same dead pages.
      expect(radio.reseedForTest(), isFalse);
    });

    test('a detached station does not re-seed itself back to life', () {
      radio.attach(seed: 'seed');
      radio.offerForTest(['a']);
      radio.detach();
      expect(radio.reseedForTest(), isFalse,
          reason: 'something else is playing; this station is over');
    });
  });
}
