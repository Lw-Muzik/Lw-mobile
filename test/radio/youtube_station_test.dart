/// Which tracks of a YouTube radio page are actually new.
///
/// Measured against the real service, consecutive pages of a station overlap:
/// page two of a sample station repeated ten of page one's forty-nine tracks.
/// Nothing used to notice, so those ten were appended a second time — and a
/// station that keeps handing back what you already have is one that appears to
/// have run out of ideas.
///
/// The "entirely overlap" case is the one that stopped a station dead: such a
/// page contributes nothing, the queue does not grow, no index change fires,
/// and nothing ever asks for another page. Reading "nothing new" as *turn the
/// page* rather than *give up* is the difference between endless and nine.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/services/radio/youtube_station.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';

YtTrack track(String id) => YtTrack(videoId: id, title: 'Track $id');

List<String> idsOf(List<YtTrack> tracks) => [for (final t in tracks) t.videoId];

void main() {
  late YouTubeStation station;
  setUp(() => station = YouTubeStation(seed: 'seed'));

  test('a first page is all new', () {
    expect(
      idsOf(station.freshTracksForTest(
        [track('a'), track('b'), track('c')],
        exclude: {},
        limit: 10,
      )),
      ['a', 'b', 'c'],
    );
  });

  test('a track already offered is not offered again', () {
    expect(
      idsOf(station.freshTracksForTest(
        [track('b'), track('c')],
        exclude: {'b'},
        limit: 10,
      )),
      ['c'],
      reason: 'page overlap is normal and must not reach the queue twice',
    );
  });

  test('a page repeating itself yields each track once', () {
    expect(
      idsOf(station.freshTracksForTest(
        [track('a'), track('a'), track('b')],
        exclude: {},
        limit: 10,
      )),
      ['a', 'b'],
    );
  });

  test('a page that is entirely overlap yields nothing', () {
    expect(
      station.freshTracksForTest(
        [track('a'), track('b')],
        exclude: {'a', 'b'},
        limit: 10,
      ),
      isEmpty,
      reason: 'the caller has to read this as "turn the page", not "stop"',
    );
  });

  test('the limit bounds how many are taken, not how many are seen', () {
    final page = [for (var i = 0; i < 40; i++) track('t$i')];
    final first = station.freshTracksForTest(page, exclude: {}, limit: 25);
    expect(first.length, 25);
    // The fifteen left behind were never handed over, so the next fill — which
    // excludes only what was actually taken — still finds them.
    final second = station.freshTracksForTest(
      page,
      exclude: idsOf(first).toSet(),
      limit: 25,
    );
    expect(idsOf(second), idsOf(page.sublist(25)));
  });

  test('the seed itself is never offered back', () {
    expect(
      idsOf(station.freshTracksForTest(
        [track('seed'), track('a')],
        exclude: {'seed'},
        limit: 10,
      )),
      ['a'],
      reason: 'the song that started the station is already playing',
    );
  });

  group('the seed and its cursor', () {
    test('walking forward clears the cursor', () {
      expect(station.advanceSeed('other'), isTrue);
      expect(station.seedKey, 'other');
    });

    test('it will not walk onto the seed it already has', () {
      expect(station.advanceSeed('seed'), isFalse);
    });

    // A new station is a new object, so there is nowhere for the previous
    // station's cursor to survive. That used to be a guard; now it is a shape.
    test('a fresh station shares nothing with the previous one', () {
      final first = YouTubeStation(seed: 'first');
      first.advanceSeed('somewhere');
      final second = YouTubeStation(seed: 'second');
      expect(second.seedKey, 'second');
    });
  });
}
