/// Which tracks of a radio page are actually new.
///
/// Measured against the real service, consecutive pages of a station overlap:
/// page two of a sample station repeated ten of page one's forty-nine tracks.
/// Nothing used to notice, so those ten were appended a second time — and a
/// station that keeps handing back what you already have is one that appears to
/// have run out of ideas.
///
/// The second case here is the one that stops a station dead: a page that is
/// *entirely* overlap contributes nothing, the queue does not grow, no index
/// change fires, and nothing ever asks for another page. Recognising "nothing
/// new" as a reason to turn the page rather than to give up is the difference
/// between endless and nine.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/services/ytmusic/yt_models.dart';
import 'package:eq_app/services/ytmusic/yt_playback.dart';

YtTrack track(String id) => YtTrack(videoId: id, title: 'Track $id');

List<String> idsOf(List<YtTrack> tracks) => [for (final t in tracks) t.videoId];

void main() {
  final radio = YtRadioQueue.instance;

  setUp(radio.resetForTest);

  test('a first page is all new', () {
    final fresh = radio.freshTracksForTest(
      [track('a'), track('b'), track('c')],
      limit: 10,
    );
    expect(idsOf(fresh), ['a', 'b', 'c']);
  });

  test('a track already offered is not offered again', () {
    radio.freshTracksForTest([track('a'), track('b')], limit: 10);
    final fresh =
        radio.freshTracksForTest([track('b'), track('c')], limit: 10);
    expect(idsOf(fresh), ['c'],
        reason: 'page overlap is normal and must not reach the queue twice');
  });

  test('a page repeating itself yields each track once', () {
    final fresh = radio.freshTracksForTest(
      [track('a'), track('a'), track('b')],
      limit: 10,
    );
    expect(idsOf(fresh), ['a', 'b']);
  });

  test('a page that is entirely overlap yields nothing', () {
    radio.freshTracksForTest([track('a'), track('b')], limit: 10);
    expect(radio.freshTracksForTest([track('a'), track('b')], limit: 10),
        isEmpty,
        reason: 'the caller has to read this as "turn the page", not "stop"');
  });

  test('the limit bounds how many are taken, not how many are remembered', () {
    final page = [for (var i = 0; i < 40; i++) track('t$i')];
    final first = radio.freshTracksForTest(page, limit: 25);
    expect(first.length, 25);
    // The fifteen that were left behind are still on offer next time, because
    // they were never handed over — only the taken ones are remembered.
    final second = radio.freshTracksForTest(page, limit: 25);
    expect(idsOf(second), idsOf(page.sublist(25)));
  });

  test('the seed itself is never offered back', () {
    radio.attach(seed: 'seed1');
    final fresh = radio.freshTracksForTest(
      [track('seed1'), track('a')],
      limit: 10,
    );
    expect(idsOf(fresh), ['a'],
        reason: 'the song that started the station is already playing');
  });

  test('a new station forgets the last one', () {
    radio.attach(seed: 'seed1');
    radio.freshTracksForTest([track('a')], limit: 10);
    radio.attach(seed: 'seed2');
    final fresh = radio.freshTracksForTest([track('a')], limit: 10);
    expect(idsOf(fresh), ['a'],
        reason: 'a track heard on one station is fair game on the next');
  });

  test('detaching forgets everything too', () {
    radio.freshTracksForTest([track('a')], limit: 10);
    radio.detach();
    expect(idsOf(radio.freshTracksForTest([track('a')], limit: 10)), ['a']);
  });
}
