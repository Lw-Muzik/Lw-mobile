/// Feeding the mix engine from a real database.
///
/// The engine's own rules are tested in `daily_mixes_test.dart` with no
/// database at all. What is tested here is the wiring: that listening history
/// recorded through the repository actually reaches the engine, that the keys
/// the engine returns map back to playable tracks, and that a mix is built once
/// per daypart rather than on every read.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/data/library_database.dart';
import 'package:eq_app/data/library_repository.dart';
import 'package:eq_app/services/mixes/daily_mix_service.dart';

void main() {
  late LibraryDatabase db;
  late LibraryRepository repo;
  late DailyMixService service;

  setUp(() {
    db = LibraryDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
    service = DailyMixService(repo);
  });

  tearDown(() async => db.close());

  Future<void> insert(
    int id, {
    required String genre,
    required String artist,
    int duration = 200000,
  }) =>
      repo.upsertSongs([
        SongsCompanion.insert(
          id: Value(id),
          data: '/music/$id.mp3',
          title: Value('Track $id'),
          artist: Value(artist),
          genre: Value(genre),
          duration: Value(duration),
        ),
      ]);

  /// A cluster big and varied enough for the engine to accept as a taste.
  Future<void> insertTaste(String genre, int from, {int count = 20}) async {
    for (var i = 0; i < count; i++) {
      await insert(from + i, genre: genre, artist: '$genre artist ${i % 5}');
    }
  }

  final afternoon = DateTime(2026, 8, 26, 14);
  final evening = DateTime(2026, 8, 26, 19);

  test('an empty library produces no mixes', () async {
    expect(await service.mixes(now: afternoon), isEmpty);
  });

  test('a library with one taste produces one mix of playable tracks',
      () async {
    await insertTaste('Afrobeat', 100, count: 30);

    final mixes = await service.mixes(now: afternoon);
    expect(mixes, hasLength(1));
    expect(mixes.single.descriptor, 'Afrobeat');
    expect(mixes.single.name, 'afrobeat afternoon');
    expect(mixes.single.songs, isNotEmpty);
    // The point of resolving: these have to be real rows the player can open.
    expect(mixes.single.songs.every((s) => s.data.isNotEmpty), isTrue);
  });

  test('two tastes produce two mixes', () async {
    await insertTaste('Afrobeat', 100, count: 20);
    await insertTaste('Soul', 200, count: 20);

    final mixes = await service.mixes(now: afternoon);
    expect(mixes.map((m) => m.descriptor).toSet(), {'Afrobeat', 'Soul'});
  });

  group('listening history reaches the engine', () {
    test('a skipped track is not treated as proven', () async {
      await insertTaste('Afrobeat', 100, count: 20);
      // Ten plays, all abandoned in the first few seconds.
      for (var i = 0; i < 10; i++) {
        await repo.recordPlayEvent(
          songId: 100,
          atSec: 1700000000 + i * 3600,
          msPlayed: 2000,
          completed: false,
        );
      }

      final stats = await repo.playStats();
      expect(stats[100]!.plays, 10);
      expect(stats[100]!.skips, 10,
          reason: '2s of a 200s track is a skip by any measure');
      expect(stats[100]!.isProven, isFalse);
    });

    test('a track played through is proven', () async {
      await insertTaste('Afrobeat', 100, count: 20);
      for (var i = 0; i < 5; i++) {
        await repo.recordPlayEvent(
          songId: 101,
          atSec: 1700000000 + i * 3600,
          msPlayed: 195000,
          completed: true,
        );
      }
      final stats = await repo.playStats();
      expect(stats[101]!.skips, 0);
      expect(stats[101]!.isProven, isTrue);
    });

    test('a track with no duration cannot be judged a skip', () async {
      await insert(300, genre: 'Afrobeat', artist: 'A', duration: 0);
      await repo.recordPlayEvent(
        songId: 300, atSec: 1700000000, msPlayed: 10, completed: false);
      final stats = await repo.playStats();
      expect(stats[300]!.skips, 0,
          reason: 'unknown length means the fraction is unknowable');
    });

    test('hours of the day are recorded per track', () async {
      await insert(400, genre: 'Afrobeat', artist: 'A');
      // 1700000000 is a fixed instant; the hour is whatever it is locally, but
      // it must be the same one every time and it must be recorded.
      await repo.recordPlayEvent(
        songId: 400, atSec: 1700000000, msPlayed: 190000, completed: true);
      final hours = await repo.playHours();
      expect(hours[400], hasLength(1));
      expect(hours[400]!.single, inInclusiveRange(0, 23));
    });
  });

  group('pruning', () {
    test('history older than the retention window is dropped', () async {
      await insert(500, genre: 'Afrobeat', artist: 'A');
      const now = 1700000000;
      await repo.recordPlayEvent(
        songId: 500,
        atSec: now - (kPlayEventRetentionDays + 5) * 86400,
        msPlayed: 190000,
        completed: true,
      );
      await repo.recordPlayEvent(
        songId: 500, atSec: now - 86400, msPlayed: 190000, completed: true);

      expect(await repo.playEventCount(), 2);
      await repo.prunePlayEvents(now);
      expect(await repo.playEventCount(), 1,
          reason: 'taste from three months ago is not taste today');
    });
  });

  group('caching', () {
    test('the same daypart returns the identical list', () async {
      await insertTaste('Afrobeat', 100, count: 30);
      final first = await service.mixes(now: afternoon);
      final second = await service.mixes(now: afternoon);
      expect(identical(first, second), isTrue,
          reason: 'rebuilding produces the same answer at the cost of three '
              'queries and a clustering pass');
    });

    test('a new daypart rebuilds', () async {
      await insertTaste('Afrobeat', 100, count: 30);
      final noon = await service.mixes(now: afternoon);
      final dusk = await service.mixes(now: evening);
      expect(identical(noon, dusk), isFalse);
      expect(dusk.single.name, 'afrobeat evening');
    });

    test('force rebuilds within the same daypart', () async {
      await insertTaste('Afrobeat', 100, count: 30);
      final first = await service.mixes(now: afternoon);
      final forced = await service.mixes(now: afternoon, force: true);
      expect(identical(first, forced), isFalse);
    });

    test('invalidate drops the cache, for after a library scan', () async {
      await insertTaste('Afrobeat', 100, count: 30);
      final first = await service.mixes(now: afternoon);
      service.invalidate();
      final second = await service.mixes(now: afternoon);
      expect(identical(first, second), isFalse);
    });
  });

  group('playlists', () {
    test('a playlist can be created, filled and read back', () async {
      final id = await repo.createPlaylist('Evening', 1700000000);
      await repo.addToPlaylist(
        id,
        const [
          PlaylistItem(source: 'local', songId: 1, title: 'One'),
          PlaylistItem(
              source: 'youtube', externalId: 'abc', title: 'Two',
              artist: 'Someone'),
        ],
        1700000000,
      );

      final entries = await repo.playlistEntries(id);
      expect(entries.map((e) => e.title), ['One', 'Two']);
      // The reason a playlist can hold this at all: MediaStore playlists cannot.
      expect(entries.last.source, 'youtube');
      expect(entries.last.externalId, 'abc');
    });

    test('a summary carries its track count', () async {
      final id = await repo.createPlaylist('Evening', 1700000000);
      await repo.addToPlaylist(
        id,
        const [PlaylistItem(source: 'local', songId: 1, title: 'One')],
        1700000000,
      );
      final all = await repo.playlists();
      expect(all.single.name, 'Evening');
      expect(all.single.trackCount, 1);
    });

    test('appending keeps positions contiguous', () async {
      final id = await repo.createPlaylist('P', 1);
      await repo.addToPlaylist(
        id, const [PlaylistItem(source: 'local', title: 'A')], 1);
      await repo.addToPlaylist(
        id, const [PlaylistItem(source: 'local', title: 'B')], 2);
      final entries = await repo.playlistEntries(id);
      expect(entries.map((e) => e.title), ['A', 'B']);
    });

    test('deleting a playlist takes its entries with it', () async {
      final id = await repo.createPlaylist('P', 1);
      await repo.addToPlaylist(
        id, const [PlaylistItem(source: 'local', title: 'A')], 1);
      await repo.deletePlaylist(id);
      expect(await repo.playlists(), isEmpty);
      expect(await repo.playlistEntries(id), isEmpty);
    });
  });
}
