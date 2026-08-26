/// Upgrading a library database that already exists.
///
/// Version 1 shipped with `onCreate` only, which is correct exactly until the
/// schema changes for the first time. At that moment every install has a v1
/// file on disk; without an upgrade path drift finds no way forward and the
/// library — every scan, every play count — is gone.
///
/// So the case that matters here is not "a fresh database has the new tables".
/// It is "a database that was written by version 1, with real rows in it,
/// survives". That is built by hand below rather than by drift, because drift
/// can only create the schema it currently knows about.
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/data/library_database.dart';
import 'package:eq_app/data/library_repository.dart';

/// The v1 schema, exactly as version 1 of the app created it.
///
/// Hand-written on purpose: generating it from today's table definitions would
/// test the migration against the schema it is migrating *to*, which is the one
/// arrangement guaranteed to pass.
const _v1Songs = '''
CREATE TABLE songs (
  id INTEGER NOT NULL,
  data TEXT NOT NULL,
  uri TEXT NULL,
  display_name TEXT NOT NULL DEFAULT '',
  display_name_w_o_ext TEXT NOT NULL DEFAULT '',
  size INTEGER NOT NULL DEFAULT 0,
  album TEXT NULL,
  album_id INTEGER NULL,
  artist TEXT NULL,
  artist_id INTEGER NULL,
  genre TEXT NULL,
  genre_id INTEGER NULL,
  composer TEXT NULL,
  date_added INTEGER NULL,
  date_modified INTEGER NULL,
  duration INTEGER NULL,
  title TEXT NOT NULL DEFAULT '',
  track INTEGER NULL,
  file_extension TEXT NOT NULL DEFAULT '',
  folder_path TEXT NOT NULL DEFAULT '',
  artwork_path TEXT NULL,
  play_count INTEGER NOT NULL DEFAULT 0,
  last_played_sec INTEGER NULL,
  PRIMARY KEY (id)
)''';

const _v1Meta = '''
CREATE TABLE library_meta (
  key TEXT NOT NULL,
  value TEXT NULL,
  PRIMARY KEY (key)
)''';

/// Writes a database file exactly as version 1 left it, with rows in it.
///
/// A real file rather than `NativeDatabase.memory()`: an in-memory database
/// belongs to its connection and vanishes when that connection closes, so it
/// cannot model the one thing being tested — a file written by one version of
/// the app and opened by the next.
Future<File> writeV1Database(Directory dir) async {
  final file = File('${dir.path}/library.sqlite');
  final user = _Bootstrap(NativeDatabase(file));
  await user.customStatement(_v1Songs);
  await user.customStatement(_v1Meta);
  await user.customStatement(
    "INSERT INTO songs (id, data, title, artist, genre, play_count, last_played_sec) "
    "VALUES (1, '/music/1.mp3', 'Kept Track', 'Kaya', 'Afrobeat', 42, 1700000000)",
  );
  await user.customStatement(
    "INSERT INTO library_meta (key, value) VALUES ('last_scan', '12345')",
  );
  // What tells drift there is an upgrade to run at all.
  await user.customStatement('PRAGMA user_version = 1');
  await user.close();
  return file;
}

/// A bare drift database used only to execute raw statements against [executor].
class _Bootstrap extends GeneratedDatabase {
  _Bootstrap(super.executor);
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
  @override
  int get schemaVersion => 1;
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (_) async {});
}

void main() {
  group('a database written by version 1', () {
    late Directory dir;
    late LibraryDatabase db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('hype_migration');
      final file = await writeV1Database(dir);
      // A fresh connection to the same file — exactly what a user upgrading the
      // app gets.
      db = LibraryDatabase.forTesting(NativeDatabase(file));
      // Migrations are lazy: nothing happens until the database is used.
      await db.customSelect('SELECT 1').get();
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('keeps the songs it already had', () async {
      final rows = await db.customSelect('SELECT * FROM songs').get();
      expect(rows, hasLength(1));
      expect(rows.single.data['title'], 'Kept Track');
    });

    // The one that matters most: a play count is the only listening history a
    // v1 install has, and losing it resets the user's taste to nothing.
    test('keeps play counts and last-played times', () async {
      final row = await db.customSelect('SELECT * FROM songs').getSingle();
      expect(row.data['play_count'], 42);
      expect(row.data['last_played_sec'], 1700000000);
    });

    test('keeps scan bookkeeping, so the next launch does not rescan', () async {
      final row = await db
          .customSelect("SELECT value FROM library_meta WHERE key = 'last_scan'")
          .getSingle();
      expect(row.data['value'], '12345');
    });

    test('gains the version 2 tables', () async {
      Future<bool> exists(String table) async {
        final rows = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
              variables: [Variable<String>(table)],
            )
            .get();
        return rows.isNotEmpty;
      }

      expect(await exists('play_events'), isTrue);
      expect(await exists('playlists'), isTrue);
      expect(await exists('playlist_entries'), isTrue);
    });

    test('reports itself as version 2 afterwards', () async {
      final row =
          await db.customSelect('PRAGMA user_version').getSingle();
      expect(row.data.values.first, 2);
    });

    test('gains the indexes a fresh install would have', () async {
      final rows = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='index'")
          .get();
      final names = {for (final r in rows) r.data['name'] as String};
      expect(names, contains('idx_songs_genre'));
      expect(names, contains('idx_play_events_song'));
      expect(names, contains('idx_playlist_entries_playlist'));
    });

    test('the new tables actually work after the upgrade', () async {
      final repo = LibraryRepository(db);
      await repo.recordPlayEvent(
        songId: 1,
        atSec: 1700000100,
        msPlayed: 180000,
        completed: true,
      );
      final events = await db.customSelect('SELECT * FROM play_events').get();
      expect(events, hasLength(1));
      expect(events.single.data['song_id'], 1);
    });
  });

  group('a fresh install', () {
    late LibraryDatabase db;

    setUp(() async {
      db = LibraryDatabase.forTesting(NativeDatabase.memory());
      await db.customSelect('SELECT 1').get();
    });

    tearDown(() async => db.close());

    test('starts at version 2 with every table', () async {
      final row = await db.customSelect('PRAGMA user_version').getSingle();
      expect(row.data.values.first, 2);

      final rows = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
          .get();
      final names = {for (final r in rows) r.data['name'] as String};
      expect(names, containsAll(['songs', 'play_events', 'playlists',
        'playlist_entries', 'library_meta']));
    });

    // A migrated database that is slower than a fresh one is the usual way
    // index creation drifts between onCreate and onUpgrade.
    test('has the same indexes an upgraded one gets', () async {
      final rows = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='index'")
          .get();
      final names = {for (final r in rows) r.data['name'] as String};
      expect(names, containsAll([
        'idx_songs_title',
        'idx_songs_artist',
        'idx_songs_album',
        'idx_songs_date_added',
        'idx_songs_folder',
        'idx_songs_genre',
        'idx_play_events_song',
        'idx_play_events_at',
        'idx_playlist_entries_playlist',
      ]));
    });
  });
}
