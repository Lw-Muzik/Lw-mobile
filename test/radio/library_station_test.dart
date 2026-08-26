/// A station built out of the user's own files, end to end.
///
/// The scorer is tested on its own in `track_similarity_test.dart`. What is
/// tested here is everything around it: that the database narrowing does not
/// hide the music it should be finding, that a drawn track becomes a real queue
/// entry, and that the station can still walk forward when its first seed is
/// spent.
library;

import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/data/library_database.dart';
import 'package:eq_app/data/library_repository.dart';
import 'package:eq_app/services/radio/library_station.dart';

void main() {
  late LibraryDatabase db;
  late LibraryRepository repo;

  setUp(() {
    db = LibraryDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insert(
    int id, {
    String title = 'Track',
    String? artist,
    String? album,
    String? genre,
    int? dateAdded,
    int playCount = 0,
  }) =>
      repo.upsertSongs([
        SongsCompanion.insert(
          id: Value(id),
          data: '/music/$id.mp3',
          title: Value(title),
          artist: Value(artist),
          album: Value(album),
          genre: Value(genre),
          dateAdded: Value(dateAdded),
          playCount: Value(playCount),
        ),
      ]);

  group('finding candidates', () {
    test('an artist match is found', () async {
      await insert(1, artist: 'Kaya');
      await insert(2, artist: 'Kaya');
      await insert(3, artist: 'Nobody');

      final found = await repo.stationCandidates(artist: 'Kaya', wander: 0);
      expect(found.map((s) => s.id), containsAll([1, 2]));
      expect(found.map((s) => s.id), isNot(contains(3)));
    });

    test('matching ignores case', () async {
      await insert(1, artist: 'Kaya');
      final found = await repo.stationCandidates(artist: 'kAyA', wander: 0);
      expect(found.map((s) => s.id), contains(1));
    });

    test('a genre or album match counts too', () async {
      await insert(1, artist: 'A', genre: 'Afrobeat');
      await insert(2, artist: 'B', album: 'Sunrise');
      final found = await repo.stationCandidates(
        artist: 'Nobody',
        genre: 'Afrobeat',
        album: 'Sunrise',
        wander: 0,
      );
      expect(found.map((s) => s.id), containsAll([1, 2]));
    });

    // Otherwise every untagged file in the library is "related" to every other,
    // and a station seeded on one of them is a station of everything.
    test('"Unknown Artist" is not a constraint', () async {
      await insert(1, artist: 'Unknown Artist');
      await insert(2, artist: 'Unknown Artist');
      final found =
          await repo.stationCandidates(artist: 'Unknown Artist', wander: 0);
      expect(found, isEmpty);
    });

    test('a blank field is not a constraint', () async {
      await insert(1, artist: '   ');
      final found = await repo.stationCandidates(artist: '   ', wander: 0);
      expect(found, isEmpty);
    });

    test('the wandering sample reaches music the seed has nothing to do with',
        () async {
      await insert(1, artist: 'Kaya');
      for (var i = 2; i < 12; i++) {
        await insert(i, artist: 'Nobody', genre: 'Polka');
      }
      final found = await repo.stationCandidates(artist: 'Kaya', wander: 50);
      expect(found.length, greaterThan(1),
          reason: 'a station that can only draw exact matches can never leave '
              'the artist it started on');
    });

    test('a track reached by both queries appears once', () async {
      await insert(1, artist: 'Kaya');
      final found = await repo.stationCandidates(artist: 'Kaya', wander: 50);
      expect(found.where((s) => s.id == 1).length, 1);
    });
  });

  group('the station itself', () {
    test('draws playable entries related to the seed', () async {
      await insert(1, title: 'Seed', artist: 'Kaya', genre: 'Afrobeat');
      for (var i = 2; i < 12; i++) {
        await insert(i, title: 'Kaya $i', artist: 'Kaya', genre: 'Afrobeat');
      }
      final seed = (await repo.allSongs()).firstWhere((s) => s.id == 1);

      final station =
          LibraryStation(repo: repo, seed: seed, random: Random(1));
      final batch = await station.fetch(exclude: {'1'}, limit: 5);

      expect(batch.tracks, hasLength(5));
      expect(batch.tracks.map((s) => s.id), isNot(contains(1)));
      expect(batch.consumed, hasLength(5));
      expect(batch.tracks.every((s) => s.data.isNotEmpty), isTrue);
    });

    test('an empty library yields an empty batch rather than throwing',
        () async {
      await insert(1, title: 'Seed', artist: 'Kaya');
      final seed = (await repo.allSongs()).single;
      await repo.deleteSongs([]); // no-op; the point is the library has one row

      final station = LibraryStation(repo: repo, seed: seed, random: Random(1));
      final batch = await station.fetch(exclude: {'1'}, limit: 5);
      expect(batch.tracks, isEmpty,
          reason: 'the only track in the library is the seed');
    });

    test('everything already offered is left out', () async {
      await insert(1, title: 'Seed', artist: 'Kaya');
      await insert(2, artist: 'Kaya');
      await insert(3, artist: 'Kaya');
      final seed = (await repo.allSongs()).firstWhere((s) => s.id == 1);

      final station = LibraryStation(repo: repo, seed: seed, random: Random(1));
      final batch = await station.fetch(exclude: {'1', '2'}, limit: 10);

      expect(batch.tracks.map((s) => s.id), [3]);
    });

    test('the seed can be walked forward onto a track it already offered',
        () async {
      await insert(1, title: 'Seed', artist: 'Kaya');
      await insert(2, title: 'Next', artist: 'Kaya');
      final seed = (await repo.allSongs()).firstWhere((s) => s.id == 1);

      final station = LibraryStation(repo: repo, seed: seed, random: Random(1));
      await station.fetch(exclude: {'1'}, limit: 10);

      expect(station.advanceSeed('2'), isTrue);
      expect(station.seedKey, '2');
    });

    test('it refuses to walk onto a track it never offered', () async {
      await insert(1, title: 'Seed', artist: 'Kaya');
      final seed = (await repo.allSongs()).single;
      final station = LibraryStation(repo: repo, seed: seed, random: Random(1));

      expect(station.advanceSeed('999'), isFalse);
      expect(station.seedKey, '1');
    });
  });
}
