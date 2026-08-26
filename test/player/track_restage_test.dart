/// When a queue entry has to be resolved again before it can be played.
///
/// The interesting case is the one that looks fine. A YouTube *video* carries a
/// deadline like any other streamed track, but what the player actually opens is
/// a DASH manifest written to disk — and manifests are swept at every launch, by
/// design, because one left over from a previous run has no queue entry pointing
/// at it. So a video killed two minutes after it resolved comes back with a
/// perfectly live deadline and nothing behind it. Trusting the deadline alone
/// hands the player a path to a file that is not there.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'package:eq_app/models/track_extras.dart';

/// Unix seconds, [offset] from now.
int at(Duration offset) =>
    DateTime.now().add(offset).millisecondsSinceEpoch ~/ 1000;

SongModel local() => SongModel({
      '_id': 1,
      '_data': '/music/1.mp3',
      'title': 'Track',
      '_display_name': '1.mp3',
      '_display_name_wo_ext': '1',
      '_size': 0,
      'file_extension': 'mp3',
      'is_music': true,
    });

SongModel streamed({
  required bool isVideo,
  int? expiresAt,
}) =>
    SongModel({
      '_id': 2,
      '_data': isVideo ? '/tmp/hype_video/abc.mpd' : 'https://googlevideo/abc',
      'title': 'Streamed',
      '_display_name': 'abc',
      '_display_name_wo_ext': 'abc',
      '_size': 0,
      'file_extension': isVideo ? 'mpd' : 'm4a',
      'is_music': true,
      TrackKeys.videoId: 'abc',
      TrackKeys.isVideo: isVideo,
      TrackKeys.expiresAt: ?expiresAt,
    });

void main() {
  group('a track that never came from YouTube', () {
    test('is never refreshed, staged or not', () {
      expect(local().needsRefresh(staged: false), isFalse);
      expect(local().needsRefresh(staged: true), isFalse);
    });
  });

  group('an audio stream', () {
    test('with a live deadline is left alone', () {
      final song = streamed(isVideo: false, expiresAt: at(const Duration(hours: 2)));
      expect(song.needsRefresh(staged: false), isFalse);
    });

    test('with an expired deadline is refreshed', () {
      final song = streamed(isVideo: false, expiresAt: at(const Duration(hours: -1)));
      expect(song.needsRefresh(staged: false), isTrue);
    });

    test('with no deadline at all is refreshed rather than guessed at', () {
      expect(streamed(isVideo: false).needsRefresh(staged: false), isTrue);
    });

    test('is not affected by whether a manifest is staged', () {
      final song = streamed(isVideo: false, expiresAt: at(const Duration(hours: 2)));
      expect(song.needsRefresh(staged: true), isFalse);
      expect(song.needsRefresh(staged: false), isFalse);
    });
  });

  group('a video', () {
    test('with a live deadline AND a staged manifest is left alone', () {
      final song = streamed(isVideo: true, expiresAt: at(const Duration(hours: 2)));
      expect(song.needsRefresh(staged: true), isFalse);
    });

    // The regression this file exists for: the deadline is honest, the file is
    // gone, and the old check said "fresh".
    test('with a live deadline but NO staged manifest is restaged', () {
      final song = streamed(isVideo: true, expiresAt: at(const Duration(hours: 2)));
      expect(song.needsRefresh(staged: false), isTrue);
    });

    test('with an expired deadline is refreshed even while staged', () {
      final song = streamed(isVideo: true, expiresAt: at(const Duration(hours: -1)));
      expect(song.needsRefresh(staged: true), isTrue);
    });

    test('a deadline inside the minute of headroom counts as expired', () {
      final song = streamed(isVideo: true, expiresAt: at(const Duration(seconds: 30)));
      expect(song.needsRefresh(staged: true), isTrue);
    });
  });
}
