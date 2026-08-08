/// Putting a queue in and out of shuffled order.
///
/// Extracted from `AppController` and tested on its own because the bug it
/// replaces was pure list arithmetic that happened to be spread across a
/// getter, two methods and a button's tap handler — the ordering was correct in
/// none of them and the failure was invisible until a track ended.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'package:eq_app/controllers/queue_order.dart';

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

void main() {
  final queue = [for (var i = 0; i < 8; i++) song(i)];

  group('shuffling', () {
    test('keeps every track exactly once', () {
      final shuffled = QueueOrder.shuffle(queue, queue[3], seed: 1);
      expect(ids(shuffled)..sort(), ids(queue)..sort());
      expect(shuffled.length, queue.length);
    });

    test('puts the playing track first so it is not interrupted', () {
      final shuffled = QueueOrder.shuffle(queue, queue[5], seed: 1);
      expect(shuffled.first.id, 5,
          reason: 'shuffling must not restart what is already playing');
    });

    test('actually changes the order', () {
      final shuffled = QueueOrder.shuffle(queue, queue[0], seed: 1);
      expect(ids(shuffled), isNot(ids(queue)));
    });

    test('a queue with nothing playing still shuffles', () {
      final shuffled = QueueOrder.shuffle(queue, null, seed: 1);
      expect(ids(shuffled)..sort(), ids(queue)..sort());
    });

    test('a track that is not in the queue does not smuggle itself in', () {
      final shuffled = QueueOrder.shuffle(queue, song(99), seed: 1);
      expect(ids(shuffled)..sort(), ids(queue)..sort(),
          reason: 'a stale current track would otherwise be added to the queue');
    });

    test('an empty queue shuffles to an empty queue', () {
      expect(QueueOrder.shuffle(const <SongModel>[], null, seed: 1), isEmpty);
    });

    test('a single track is its own shuffle', () {
      final one = [song(1)];
      expect(ids(QueueOrder.shuffle(one, one.first, seed: 1)), [1]);
    });
  });

  group('finding a track again', () {
    test('locates the playing track in the original order', () {
      // The whole point of unshuffling: the track playing at shuffled position
      // 0 has to be found at whatever position it holds in the real queue.
      final shuffled = QueueOrder.shuffle(queue, queue[6], seed: 1);
      expect(QueueOrder.indexOf(queue, shuffled.first), 6);
    });

    test('identity is the song id, not object equality', () {
      // The two lists hold different SongModel instances built from the same
      // row; comparing by reference would find nothing and silently return 0.
      expect(QueueOrder.indexOf(queue, song(4)), 4);
    });

    test('a track that has gone falls back to the start, not to -1', () {
      expect(QueueOrder.indexOf(queue, song(99)), 0,
          reason: 'a negative index would be used to subscript the queue');
    });

    test('nothing playing means the start', () {
      expect(QueueOrder.indexOf(queue, null), 0);
    });

    test('an empty queue has no position to return but must be safe', () {
      expect(QueueOrder.indexOf(const <SongModel>[], song(1)), 0);
    });
  });

  group('round trip', () {
    test('shuffling and unshuffling returns to the same track', () {
      for (var playing = 0; playing < queue.length; playing++) {
        final shuffled = QueueOrder.shuffle(queue, queue[playing], seed: playing);
        final restored = QueueOrder.indexOf(queue, shuffled.first);
        expect(restored, playing,
            reason: 'unshuffling jumped from track $playing to track $restored');
      }
    });
  });
}
