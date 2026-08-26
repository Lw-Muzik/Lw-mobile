import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'library_database.g.dart';

/// How long a listening event is worth keeping.
///
/// Long enough to see a season's habits, short enough that the log stays small
/// and that taste from last year stops colouring today's mixes.
const int kPlayEventRetentionDays = 90;

/// How far through a track counts as having listened to it.
///
/// Below this and the play reads as a skip. Thirty per cent is deliberately
/// generous: leaving a track a third of the way in is a judgement, while
/// leaving it at eighty per cent is usually just moving on.
const double kSkipFraction = 0.3;

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

/// One thing the user did with one track.
///
/// # Why an event log rather than more columns on [Songs]
///
/// `playCount` answers "how often", and that is the only question the library
/// could answer about taste. It cannot say whether a track was *finished* or
/// skipped ten seconds in, and it cannot say *when* — and those two are what
/// separate a personal mix from "your most played, shuffled".
///
/// Denormalised counters would need one column per question and could never
/// answer a question nobody had thought of yet. One row per track change costs
/// a single insert and every one of those answers derives from it: play counts,
/// skip rate, an hour-of-day histogram.
///
/// Pruned to [kPlayEventRetentionDays]; taste from three months ago is not
/// taste today, and an unbounded log on a phone is a bug waiting to happen.
class PlayEvents extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The [Songs] id. Not a foreign key: a track can leave the library while its
  /// history is still worth keeping, and a scan that removes a file must not
  /// have to reason about history to do it.
  IntColumn get songId => integer()();

  /// Unix seconds when the track *started*.
  IntColumn get atSec => integer()();

  /// How long it actually played. Zero is meaningful — it means "started and
  /// left immediately", which is the strongest negative signal there is.
  IntColumn get msPlayed => integer().withDefault(const Constant(0))();

  /// Whether it ran to its natural end rather than being skipped past.
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
}

/// A playlist the app owns.
///
/// # Why not MediaStore's
///
/// `OnAudioQuery.queryPlaylists` is **Android-only** — it is documented in
/// `play_list_view.dart` as crashing on iOS — so half the platforms have no
/// playlists at all. And a MediaStore playlist can only hold MediaStore ids, so
/// it cannot hold a track from a cloud drive, a track from YouTube, or a saved
/// daily mix.
///
/// App-owned rows fix both. MediaStore playlists stay readable and are imported
/// once on Android; this table is the single writer from then on.
class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get createdSec => integer()();
  IntColumn get updatedSec => integer()();

  /// Artwork chosen for the playlist, or null to fall back to its first track.
  TextColumn get coverPath => text().nullable()();
}

/// One track in a playlist, in order.
class PlaylistEntries extends Table {
  IntColumn get playlistId => integer()();

  /// Position within the playlist, from zero.
  IntColumn get position => integer()();

  /// Where this entry comes from: `local`, `cloud` or `youtube`.
  TextColumn get source => text().withDefault(const Constant('local'))();

  /// The [Songs] id for a local entry; null otherwise.
  IntColumn get songId => integer().nullable()();

  /// The provider's own id for a non-local entry — a drive file id, a YouTube
  /// video id. Null for local entries.
  TextColumn get externalId => text().nullable()();

  /// Title and artist are stored here as well as at the source.
  ///
  /// A playlist has to render before its cloud links are minted or its YouTube
  /// ids resolved, and a row that says nothing until the network answers is a
  /// row that looks broken offline.
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get artist => text().nullable()();

  @override
  Set<Column> get primaryKey => {playlistId, position};
}

/// Small key/value store for scan bookkeeping (last MediaStore signature, last
/// scan time) so a launch with an unchanged library does zero query work.
class LibraryMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Songs, PlayEvents, Playlists, PlaylistEntries, LibraryMeta])
class LibraryDatabase extends _$LibraryDatabase {
  LibraryDatabase() : super(_openConnection());

  /// In-memory database for unit tests.
  LibraryDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  /// # Why this has an `onUpgrade` and did not before
  ///
  /// Version 1 shipped with `onCreate` only. That is correct exactly until the
  /// schema changes for the first time — at which point every existing install
  /// has a version-1 file on disk, drift finds no upgrade path, and the library
  /// database is lost. A schema change without an upgrade path is not a
  /// migration; it is a wipe with extra steps.
  ///
  /// Version 2 adds listening history and app-owned playlists. It **adds** only:
  /// nothing in `songs` is altered, so an upgrade cannot lose a scan, and a user
  /// arriving from v1 keeps every play count they had.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(playEvents);
            await m.createTable(playlists);
            await m.createTable(playlistEntries);
          }
          // Re-run unconditionally: every statement is `IF NOT EXISTS`, and an
          // index that failed to be created once should not stay missing for
          // the life of the install.
          await _createIndexes();
        },
        beforeOpen: (details) async {
          // Foreign keys are off by default in SQLite and nothing here declares
          // any; stated so the absence is a decision rather than an oversight.
          // A track can leave the library while its history stays.
          await customStatement('PRAGMA foreign_keys = OFF');
        },
      );

  /// Every index the app relies on, in one place so `onCreate` and `onUpgrade`
  /// cannot drift apart — the usual way a migrated database ends up slower than
  /// a fresh one.
  Future<void> _createIndexes() async {
    const statements = [
      // Covering every sort/filter the browsing UI issues.
      'CREATE INDEX IF NOT EXISTS idx_songs_title ON songs (title COLLATE NOCASE)',
      'CREATE INDEX IF NOT EXISTS idx_songs_artist ON songs (artist COLLATE NOCASE)',
      'CREATE INDEX IF NOT EXISTS idx_songs_album ON songs (album COLLATE NOCASE)',
      'CREATE INDEX IF NOT EXISTS idx_songs_date_added ON songs (date_added)',
      'CREATE INDEX IF NOT EXISTS idx_songs_folder ON songs (folder_path)',
      // Genre drives clustering for daily mixes; without this every mix is a
      // full table scan.
      'CREATE INDEX IF NOT EXISTS idx_songs_genre ON songs (genre COLLATE NOCASE)',
      // History is always read by track or by time, never scanned whole.
      'CREATE INDEX IF NOT EXISTS idx_play_events_song ON play_events (song_id)',
      'CREATE INDEX IF NOT EXISTS idx_play_events_at ON play_events (at_sec)',
      'CREATE INDEX IF NOT EXISTS idx_playlist_entries_playlist ON playlist_entries (playlist_id, position)',
    ];
    for (final statement in statements) {
      await customStatement(statement);
    }
  }
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
