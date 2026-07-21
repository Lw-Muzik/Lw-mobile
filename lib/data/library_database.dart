import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'library_database.g.dart';

/// Mirror of a MediaStore audio row plus a few app-owned columns
/// (`artworkPath`, `playCount`, `lastPlayedSec`). This table is the single
/// source of truth for the browsing UI — the loader renders from it instantly
/// and [LibraryScanner] keeps it in sync by diffing MediaStore, so the whole
/// library is never re-queried on the UI isolate at launch.
class Songs extends Table {
  /// MediaStore `_id`. Stable per file, so it doubles as our primary key and
  /// the diff key alongside [dateModified].
  IntColumn get id => integer()();

  TextColumn get data => text()();
  TextColumn get uri => text().nullable()();
  TextColumn get displayName => text().withDefault(const Constant(''))();
  TextColumn get displayNameWOExt => text().withDefault(const Constant(''))();
  IntColumn get size => integer().withDefault(const Constant(0))();

  TextColumn get album => text().nullable()();
  IntColumn get albumId => integer().nullable()();
  TextColumn get artist => text().nullable()();
  IntColumn get artistId => integer().nullable()();
  TextColumn get genre => text().nullable()();
  IntColumn get genreId => integer().nullable()();
  TextColumn get composer => text().nullable()();

  IntColumn get dateAdded => integer().nullable()();
  IntColumn get dateModified => integer().nullable()();
  IntColumn get duration => integer().nullable()();

  TextColumn get title => text().withDefault(const Constant(''))();
  IntColumn get track => integer().nullable()();
  TextColumn get fileExtension => text().withDefault(const Constant(''))();

  /// Parent directory of [data] (everything up to the last `/`). Derived once
  /// at insert time so the Folders tab is a `GROUP BY`, not a per-card scan.
  TextColumn get folderPath => text().withDefault(const Constant(''))();

  /// Path to the on-disk extracted artwork PNG, filled lazily by
  /// `ArtworkService` the first time a tile becomes visible. Null = not yet
  /// resolved (never blocks the scan).
  TextColumn get artworkPath => text().nullable()();

  IntColumn get playCount => integer().withDefault(const Constant(0))();
  IntColumn get lastPlayedSec => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Small key/value store for scan bookkeeping (last MediaStore signature, last
/// scan time) so a launch with an unchanged library does zero query work.
class LibraryMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Songs, LibraryMeta])
class LibraryDatabase extends _$LibraryDatabase {
  LibraryDatabase() : super(_openConnection());

  /// In-memory database for unit tests.
  LibraryDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Indexes covering every sort/filter the browsing UI issues.
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_songs_title ON songs (title COLLATE NOCASE)');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_songs_artist ON songs (artist COLLATE NOCASE)');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_songs_album ON songs (album COLLATE NOCASE)');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_songs_date_added ON songs (date_added)');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_songs_folder ON songs (folder_path)');
        },
      );
}

/// Opens the library DB on a background isolate ([NativeDatabase.createInBackground])
/// so every read and write executes off the UI thread.
QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'hype_library.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
