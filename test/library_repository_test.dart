import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/data/library_database.dart';
import 'package:eq_app/data/library_repository.dart';
import 'package:eq_app/services/artwork_service.dart';

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

  SongsCompanion song(
    int id, {
    String title = '',
    String? artist,
    String? album,
    String? genre,
    int? dateAdded,
    int? duration,
    String folder = '/music',
    int? track,
  }) {
    return SongsCompanion.insert(
      id: Value(id),
      data: '$folder/$id.mp3',
      title: Value(title),
      artist: Value(artist),
      album: Value(album),
      genre: Value(genre),
      dateAdded: Value(dateAdded),
      duration: Value(duration),
      track: Value(track),
      folderPath: Value(folder),
    );
  }

  group('sorting', () {
    test('title sort is case-insensitive both directions', () async {
      await repo.upsertSongs([
        song(1, title: 'banana'),
        song(2, title: 'Apple'),
        song(3, title: 'cherry'),
      ]);
      final asc = await repo.allSongs(sort: SongSort.title, dir: SortDir.asc);
      expect(asc.map((s) => s.title).toList(), ['Apple', 'banana', 'cherry']);
      final desc = await repo.allSongs(sort: SongSort.title, dir: SortDir.desc);
      expect(desc.map((s) => s.title).toList(), ['cherry', 'banana', 'Apple']);
    });

    test('dateAdded desc orders newest first', () async {
      await repo.upsertSongs([
        song(1, dateAdded: 100),
        song(2, dateAdded: 300),
        song(3, dateAdded: 200),
      ]);
      final r = await repo.allSongs(sort: SongSort.dateAdded, dir: SortDir.desc);
      expect(r.map((s) => s.id).toList(), [2, 3, 1]);
    });
  });

  group('scan diff primitives', () {
    test('upsert updates an existing row rather than duplicating', () async {
      await repo.upsertSongs([song(1, title: 'old')]);
      await repo.upsertSongs([song(1, title: 'new')]);
      expect(await repo.songCount(), 1);
      final rows = await repo.allSongs();
      expect(rows.single.title, 'new');
    });

    test('existingModifiedById + deleteSongs reflect the current set', () async {
      await repo.upsertSongs([song(1), song(2), song(3)]);
      expect((await repo.existingModifiedById()).keys.toSet(), {1, 2, 3});
      await repo.deleteSongs([2]);
      expect((await repo.existingModifiedById()).keys.toSet(), {1, 3});
    });
  });

  group('search', () {
    test('matches title, artist, and album via LIKE', () async {
      await repo.upsertSongs([
        song(1, title: 'Hello World', artist: 'X'),
        song(2, title: 'Z', artist: 'Adele'),
        song(3, title: 'Q', album: 'Hello Album'),
      ]);
      expect((await repo.searchSongs('hello')).map((s) => s.id).toSet(), {1, 3});
      expect((await repo.searchSongs('adele')).single.id, 2);
      expect(await repo.searchSongs('nomatch'), isEmpty);
    });
  });

  group('derived groupings', () {
    test('albums are grouped with correct counts', () async {
      await repo.upsertSongs([
        song(1, album: 'A', artist: 'x'),
        song(2, album: 'A', artist: 'x'),
        song(3, album: 'B', artist: 'y'),
      ]);
      final albums = await repo.watchAlbums().first;
      final byName = {for (final a in albums) a.album: a.numOfSongs};
      expect(byName['A'], 2);
      expect(byName['B'], 1);
    });

    test('empty album name collapses to "Unknown Album"', () async {
      await repo.upsertSongs([song(1, album: ''), song(2)]);
      final albums = await repo.watchAlbums().first;
      expect(albums.single.album, 'Unknown Album');
      expect(albums.single.numOfSongs, 2);
    });

    test('genres exclude null/empty genre rows', () async {
      await repo.upsertSongs([
        song(1, genre: 'Rock'),
        song(2, genre: 'Rock'),
        song(3, genre: ''),
        song(4),
      ]);
      final genres = await repo.watchGenres().first;
      expect(genres.length, 1);
      expect(genres.single.genre, 'Rock');
      expect(genres.single.numOfSongs, 2);
    });

    test('folders are grouped with sample track and count', () async {
      await repo.upsertSongs([
        song(1, folder: '/m/rock'),
        song(2, folder: '/m/rock'),
        song(3, folder: '/m/jazz'),
      ]);
      final folders = await repo.watchFolders().first;
      final byPath = {for (final f in folders) f.path: f};
      expect(byPath['/m/rock']!.numSongs, 2);
      expect(byPath['/m/rock']!.name, 'rock');
      expect(byPath['/m/rock']!.sampleId, isNotNull);
      expect(byPath['/m/jazz']!.numSongs, 1);
    });

    test('album detail filters by name and orders by track', () async {
      await repo.upsertSongs([
        song(1, album: 'A', title: 'b', track: 2),
        song(2, album: 'A', title: 'a', track: 1),
        song(3, album: 'B', title: 'c'),
      ]);
      final songs = await repo.watchAlbumSongs('A').first;
      expect(songs.map((s) => s.id).toList(), [2, 1]);
    });
  });

  group('play counts', () {
    test('incrementPlayCount drives mostPlayed ordering', () async {
      await repo.upsertSongs([song(1, title: 'a'), song(2, title: 'b')]);
      await repo.incrementPlayCount(2, 1000);
      await repo.incrementPlayCount(2, 1001);
      await repo.incrementPlayCount(1, 1002);
      final most = await repo.mostPlayed(limit: 10);
      expect(most.map((s) => s.id).toList(), [2, 1]);
    });

    test('importPlayCounts applies to existing rows and ignores unknown ids',
        () async {
      await repo.upsertSongs([song(1), song(2)]);
      await repo.importPlayCounts({1: 5, 2: 3, 999: 7});
      final most = await repo.mostPlayed(limit: 10);
      expect(most.map((s) => s.id).toList(), [1, 2]);
    });
  });

  group('reactive streams', () {
    test('watchSongs emits again after an upsert', () async {
      final emissions = <int>[];
      final sub = repo.watchSongs().listen((rows) => emissions.add(rows.length));
      await pumpEventQueue();
      await repo.upsertSongs([song(1), song(2)]);
      await pumpEventQueue();
      await sub.cancel();
      expect(emissions.last, 2);
    });
  });

  group('artwork LRU', () {
    test('evicts oldest beyond the cap and keeps recent entries', () {
      final svc = ArtworkService.instance;
      svc.clearMemory();
      for (var i = 0; i < 650; i++) {
        svc.rememberForTest('k$i', '/tmp/$i.png');
      }
      // Capacity is 600; the first 50 keys should have been evicted.
      expect(svc.memoryEntries, 600);
      expect(svc.memoryPathForTest('k0'), isNull);
      expect(svc.memoryPathForTest('k649'), '/tmp/649.png');
      svc.clearMemory();
    });
  });
}
