/// Restoring where the user left off.
///
/// The file this reads was written by a previous run of the app — possibly a
/// previous release of it. Every case here is one where trusting it would end
/// a launch: a queue longer than the cap, a shuffled order pointing at tracks
/// that are gone, an index past the end, fields a past version never wrote.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'package:eq_app/models/track_extras.dart';
import 'package:eq_app/services/playback_session.dart';

SongModel song(int id) => SongModel({
      '_id': id,
      '_data': '/music/$id.mp3',
      'title': 'Track $id',
      'artist': 'Artist',
      'album': 'Album',
      'duration': 1000,
      '_display_name': '$id.mp3',
      '_display_name_wo_ext': '$id',
      '_size': 0,
      'file_extension': 'mp3',
      'is_music': true,
    });

List<int> ids(List<SongModel> list) => [for (final s in list) s.id];

/// A round trip through the encoder, which is what actually happens on disk —
/// `toJson`/`fromJson` in memory would not catch a value JSON cannot hold.
PlaybackSession? roundTrip(PlaybackSession session) => PlaybackSession.fromJson(
      Map<String, Object?>.from(jsonDecode(jsonEncode(session.toJson())) as Map),
    );

void main() {
  final queue = [for (var i = 0; i < 10; i++) song(i)];

  group('round trip', () {
    test('a plain queue survives the disk', () {
      final restored = roundTrip(PlaybackSession(
        songs: queue,
        index: 4,
        position: const Duration(seconds: 42),
        loopMode: 2,
      ));
      expect(ids(restored!.effectiveQueue), ids(queue));
      expect(restored.index, 4);
      expect(restored.position, const Duration(seconds: 42));
      expect(restored.loopMode, 2);
      expect(restored.shuffled, isFalse);
    });

    test('a shuffled queue keeps its order without storing it twice', () {
      final order = [5, 0, 9, 1, 2, 3, 4, 6, 7, 8];
      final session = PlaybackSession(
        songs: queue,
        shuffledOrder: order,
        shuffled: true,
        index: 0,
        position: Duration.zero,
      );
      expect(jsonEncode(session.toJson()).contains('"shuffledOrder"'), isTrue);
      expect(ids(roundTrip(session)!.effectiveQueue), order);
    });

    test('a streamed track keeps what it needs to be resolved again', () {
      final yt = SongModel({
        ...song(1).getMap,
        '_data': 'https://rr3---sn-x.googlevideo.com/videoplayback?expire=1',
        TrackKeys.videoId: 'dQw4w9WgXcQ',
        TrackKeys.expiresAt: 4102444800,
      });
      final restored = roundTrip(
        PlaybackSession(songs: [yt], index: 0, position: Duration.zero),
      );
      final track = restored!.effectiveQueue.single;
      expect(track.ytVideoId, 'dQw4w9WgXcQ',
          reason: 'without the id an expired URL is unrecoverable');
      expect(track.hasFreshTarget, isTrue);
    });
  });

  group('a file that cannot be trusted', () {
    test('no songs means no session', () {
      expect(PlaybackSession.fromJson(const {'songs': []}), isNull);
      expect(PlaybackSession.fromJson(const {}), isNull);
    });

    test('entries that are not maps are dropped, not fatal', () {
      final session = PlaybackSession.fromJson({
        'songs': ['nonsense', song(1).getMap, 42],
        'index': 0,
      });
      expect(ids(session!.effectiveQueue), [1]);
    });

    test('an index past the end lands on the last track', () {
      final session = PlaybackSession.fromJson({
        'songs': [for (final s in queue) s.getMap],
        'index': 999,
      });
      expect(session!.index, 9);
    });

    test('a negative index lands on the first', () {
      final session = PlaybackSession.fromJson({
        'songs': [for (final s in queue) s.getMap],
        'index': -3,
      });
      expect(session!.index, 0);
    });

    test('missing fields fall back rather than throwing', () {
      final session = PlaybackSession.fromJson({
        'songs': [song(1).getMap],
      });
      expect(session!.index, 0);
      expect(session.position, Duration.zero);
      expect(session.loopMode, 0);
      expect(session.shuffled, isFalse);
    });

    test('a shuffled order naming tracks that are gone loses nothing', () {
      final session = PlaybackSession(
        songs: queue,
        // 99 was removed from the library since the session was saved; 7 is
        // missing from the order entirely.
        shuffledOrder: const [99, 3, 1],
        shuffled: true,
        index: 0,
        position: Duration.zero,
      );
      final restored = ids(session.effectiveQueue);
      expect(restored.take(2), [3, 1], reason: 'the saved order comes first');
      expect(restored..sort(), ids(queue)..sort(),
          reason: 'every track survives, ordered or not');
    });

    test('a duplicated id in the order does not duplicate the track', () {
      final session = PlaybackSession(
        songs: queue,
        shuffledOrder: const [2, 2, 2],
        shuffled: true,
        index: 0,
        position: Duration.zero,
      );
      final restored = ids(session.effectiveQueue);
      expect(restored.length, queue.length);
      expect(restored.where((id) => id == 2).length, 1);
    });
  });

  group('windowing a queue that grew', () {
    List<SongModel> longQueue(int n) => [for (var i = 0; i < n; i++) song(i)];

    test('a queue under the cap is left alone', () {
      final session =
          PlaybackSession(songs: queue, index: 3, position: Duration.zero);
      expect(identical(session.windowed(), session), isTrue);
    });

    test('a long queue is trimmed around the playing track', () {
      final session = PlaybackSession(
        songs: longQueue(kMaxSessionTracks * 3),
        index: 900,
        position: const Duration(seconds: 5),
      );
      final windowed = session.windowed();
      expect(windowed.effectiveQueue.length, kMaxSessionTracks);
      expect(windowed.index, kSessionLookBehind,
          reason: 'the playing track keeps its place in the window');
      expect(windowed.effectiveQueue[windowed.index].id, 900,
          reason: 'the user must resume on the track they were on');
      expect(windowed.position, const Duration(seconds: 5));
    });

    test('playing near the start keeps the start', () {
      final session = PlaybackSession(
        songs: longQueue(kMaxSessionTracks * 2),
        index: 2,
        position: Duration.zero,
      );
      final windowed = session.windowed();
      expect(windowed.index, 2);
      expect(windowed.effectiveQueue.first.id, 0);
      expect(windowed.effectiveQueue[2].id, 2);
    });

    test('playing near the end keeps the end', () {
      final total = kMaxSessionTracks * 2;
      final session = PlaybackSession(
        songs: longQueue(total),
        index: total - 3,
        position: Duration.zero,
      );
      final windowed = session.windowed();
      expect(windowed.effectiveQueue.length, kMaxSessionTracks);
      expect(windowed.effectiveQueue[windowed.index].id, total - 3);
      expect(windowed.effectiveQueue.last.id, total - 1);
    });

    test('a windowed shuffled queue keeps the order it was playing in', () {
      final songs = longQueue(kMaxSessionTracks * 2);
      final order = [for (final s in songs.reversed) s.id];
      final session = PlaybackSession(
        songs: songs,
        shuffledOrder: order,
        shuffled: true,
        index: 600,
        position: Duration.zero,
      );
      final windowed = session.windowed();
      final playing = session.effectiveQueue[600].id;
      expect(windowed.effectiveQueue[windowed.index].id, playing);
      expect(windowed.effectiveQueue.length, kMaxSessionTracks);
    });

    test('a windowed session still round trips', () {
      final session = PlaybackSession(
        songs: longQueue(kMaxSessionTracks * 2),
        index: 700,
        position: const Duration(minutes: 1),
      ).windowed();
      final restored = roundTrip(session);
      expect(restored!.effectiveQueue[restored.index].id, 700);
    });
  });
}
