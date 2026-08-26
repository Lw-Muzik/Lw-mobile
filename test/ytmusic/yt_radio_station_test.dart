/// Why starting a second radio used to keep playing the first one.
///
/// A station is a seed, a continuation token and a record of what has already
/// been offered — and a fill spends seconds in the network between reading
/// those and writing them back. Start a radio, then search and play something
/// else while that fill is still in the air, and the reply lands on a station
/// the user has already left: it appends the old station's tracks to the new
/// queue, and — the part that made it survive every later track — writes the
/// *old* station's continuation token over the new one's.
///
/// A continuation token belongs to a playlist, not to a seed. Sending it with a
/// new seed returns the next page of the old station, so from that moment every
/// top-up served the radio the user had walked away from, and only killing the
/// app cleared it.
///
/// So work carries the identity of the station that asked for it, and anything
/// arriving for a station that is no longer current is dropped rather than
/// written back.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/services/ytmusic/yt_models.dart';
import 'package:eq_app/services/ytmusic/yt_playback.dart';

YtTrack track(String id) => YtTrack(videoId: id, title: 'Track $id');

List<String> idsOf(List<YtTrack> tracks) => [for (final t in tracks) t.videoId];

RadioBatch page(List<String> ids, {String? continuation}) => RadioBatch(
      tracks: [for (final id in ids) track(id)],
      continuation: continuation,
    );

void main() {
  final radio = YtRadioQueue.instance;

  setUp(radio.resetForTest);

  group('which station a fetch belongs to', () {
    test('starting another station leaves the first one behind', () {
      radio.attach(seed: 'first');
      final inFlight = radio.station;

      radio.attach(seed: 'second');

      expect(radio.isStation(inFlight), isFalse,
          reason: 'a fill still in the air was asked for by a station the '
              'user has since left');
      expect(radio.isStation(radio.station), isTrue);
    });

    test('detaching ends the station a fetch was for', () {
      radio.attach(seed: 'first');
      final inFlight = radio.station;
      radio.detach();
      expect(radio.isStation(inFlight), isFalse);
    });

    test('re-seeding is the same station walking forward', () {
      radio.attach(seed: 'first');
      final inFlight = radio.station;
      radio.offerForTest(['a']);
      radio.reseedForTest();

      expect(radio.isStation(inFlight), isTrue,
          reason: 're-seeding is how one station keeps going, not a new one — '
              'a fill in flight for it is still wanted');
    });
  });

  group('a page that arrives for a station the user has left', () {
    test('does not leave its continuation token behind', () {
      radio.attach(seed: 'first');
      final inFlight = radio.station;
      radio.attach(seed: 'second');

      radio.acceptPageForTest(inFlight, page(['a'], continuation: 'token1'),
          limit: 25);

      expect(radio.tokenForTest, isNull,
          reason: "the old station's token asks YouTube for the old station's "
              'next page — keeping it is what made the wrong radio survive '
              'every track change until the app was killed');
    });

    test('does not spend the new station\'s tracks', () {
      radio.attach(seed: 'first');
      final inFlight = radio.station;
      radio.attach(seed: 'second');

      radio.acceptPageForTest(inFlight, page(['a', 'b']), limit: 25);

      expect(idsOf(radio.freshTracksForTest([track('a')], limit: 10)), ['a'],
          reason: 'the new station never offered those, so it must not think '
              'it has');
    });

    test('yields nothing to append', () {
      radio.attach(seed: 'first');
      final inFlight = radio.station;
      radio.attach(seed: 'second');

      expect(radio.acceptPageForTest(inFlight, page(['a', 'b']), limit: 25),
          isEmpty,
          reason: 'appending these is the queue keeping the old radio');
    });
  });

  group('a page that arrives for the station that asked for it', () {
    test('is taken, and its token kept', () {
      radio.attach(seed: 'first');
      final fresh = radio.acceptPageForTest(
        radio.station,
        page(['a', 'b'], continuation: 'token1'),
        limit: 25,
      );

      expect(idsOf(fresh), ['a', 'b']);
      expect(radio.tokenForTest, 'token1');
    });

    test('still drops the seed and anything already offered', () {
      radio.attach(seed: 'first');
      radio.acceptPageForTest(radio.station, page(['a']), limit: 25);
      final second =
          radio.acceptPageForTest(radio.station, page(['first', 'a', 'b']),
              limit: 25);

      expect(idsOf(second), ['b']);
    });
  });
}
