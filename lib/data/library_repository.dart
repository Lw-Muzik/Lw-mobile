import 'package:drift/drift.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'library_database.dart';

/// Field a song list is ordered by. Values map to indexed columns.
enum SongSort { title, artist, album, dateAdded, duration, playCount }

enum SortDir { asc, desc }

/// A distinct on-disk folder with its track count and one representative track
/// (used to source the folder thumbnail without scanning the whole library).
class FolderEntry {
  const FolderEntry({
    required this.path,
    required this.name,
    required this.numSongs,
    required this.sampleData,
    this.sampleId,
  });

  final String path;
  final String name;
  final int numSongs;
  final String? sampleData;
  final int? sampleId;
}

/// How a track has actually been listened to.
///
/// Two counts rather than a ratio, because the ratio alone cannot tell "skipped
/// once out of one play" from "skipped twelve times out of forty" — and only the
/// second is evidence.
class PlayStats {
  const PlayStats({required this.plays, required this.skips});

  final int plays;
  final int skips;

  /// Fraction of plays abandoned early, or null when there is too little
  /// evidence to say. Null is not zero: never having been played is not the
  /// same as never having been skipped.
  double? get skipRate => plays < 2 ? null : skips / plays;

  /// Whether this track has earned a place in a mix on its own record.
  bool get isProven => plays >= 2 && (skipRate ?? 1) < 0.5;
}

/// A playlist as the browsing UI needs it: enough to draw a row, no tracks.
class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.trackCount,
    this.coverPath,
  });

  final int id;
  final String name;
  final int trackCount;
  final String? coverPath;
}

/// One track in a playlist, as the app talks about it.
///
/// Named `PlaylistItem` rather than `PlaylistEntry` because drift generates a
/// row class of that name from the `PlaylistEntries` table, and two types with
/// one name in the same import graph is a compile error waiting for whoever
/// imports both.
///
/// Carries its own title and artist so a playlist renders before any cloud link
/// is minted or YouTube id resolved — a row that says nothing until the network
/// answers is a row that looks broken offline.
class PlaylistItem {
  const PlaylistItem({
    required this.source,
    required this.title,
    this.songId,
    this.externalId,
    this.artist,
  });

  /// `local`, `cloud` or `youtube`.
  final String source;
  final String title;
  final int? songId;
  final String? externalId;
  final String? artist;
}

/// Reactive read/write access to the local library database.
///
/// All list getters return `Stream`s backed by drift's `watch()`, so when
/// [LibraryScanner] upserts rows the browsing UI updates live — that is what
/// makes songs appear progressively during a first-run scan and removes the
/// old "re-query MediaStore in build()" pattern. Every method reconstructs the
/// on_audio_query model objects the existing player/tile pipeline already
/// consumes, so the change is confined to where the lists come from.
class LibraryRepository {
  LibraryRepository(this._db);

  final LibraryDatabase _db;

  LibraryDatabase get db => _db;

  // ---------------------------------------------------------------------------
  // Row -> model mappers
  // ---------------------------------------------------------------------------

  SongModel _song(Map<String, dynamic> r) => SongModel({
        '_id': r['id'],
        '_data': r['data'],
        '_uri': r['uri'],
        '_display_name': r['display_name'] ?? '',
        '_display_name_wo_ext': r['display_name_wo_ext'] ?? '',
        '_size': r['size'] ?? 0,
        'album': r['album'],
        'album_id': r['album_id'],
        'artist': r['artist'],
        'artist_id': r['artist_id'],
        'genre': r['genre'],
        'genre_id': r['genre_id'],
        'composer': r['composer'],
        'date_added': r['date_added'],
        'date_modified': r['date_modified'],
        'duration': r['duration'],
        'title': r['title'] ?? '',
        'track': r['track'],
        'file_extension': r['file_extension'] ?? '',
        'is_music': true,
        // App-owned extras carried on the map so consumers that want them
        // (e.g. artwork short-circuit) can read without a second query.
        'artwork_path': r['artwork_path'],
        'play_count': r['play_count'] ?? 0,
      });

  List<SongModel> _songs(List<QueryRow> rows) =>
      rows.map((row) => _song(row.data)).toList();

  // ---------------------------------------------------------------------------
  // Songs
  // ---------------------------------------------------------------------------

  static String _songsOrderBy(SongSort sort, SortDir dir) {
    final d = dir == SortDir.asc ? 'ASC' : 'DESC';
    switch (sort) {
      case SongSort.title:
        return 'title COLLATE NOCASE $d';
      case SongSort.artist:
        return 'artist COLLATE NOCASE $d, title COLLATE NOCASE ASC';
      case SongSort.album:
        return 'album COLLATE NOCASE $d, track ASC';
      case SongSort.dateAdded:
        return 'date_added $d';
      case SongSort.duration:
        return 'duration $d';
      case SongSort.playCount:
        return 'play_count $d, last_played_sec DESC';
    }
  }

  Stream<List<SongModel>> watchSongs({
    SongSort sort = SongSort.title,
    SortDir dir = SortDir.asc,
  }) {
    return _db
        .customSelect(
          'SELECT * FROM songs ORDER BY ${_songsOrderBy(sort, dir)}',
          readsFrom: {_db.songs},
        )
        .watch()
        .map(_songs);
  }

  Future<List<SongModel>> allSongs({
    SongSort sort = SongSort.title,
    SortDir dir = SortDir.asc,
  }) async {
    final rows = await _db
        .customSelect('SELECT * FROM songs ORDER BY ${_songsOrderBy(sort, dir)}',
            readsFrom: {_db.songs})
        .get();
    return _songs(rows);
  }

  Future<int> songCount() async {
    final row = await _db
        .customSelect('SELECT COUNT(*) AS c FROM songs')
        .getSingleOrNull();
    return (row?.data['c'] as int?) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Albums / Artists / Genres (derived via GROUP BY — always consistent)
  // ---------------------------------------------------------------------------

  Stream<List<AlbumModel>> watchAlbums() {
    return _db
        .customSelect(
          "SELECT MAX(album_id) AS id, "
          "COALESCE(NULLIF(TRIM(album),''),'Unknown Album') AS name, "
          "MAX(artist) AS artist, MAX(artist_id) AS artist_id, "
          "COUNT(*) AS numsongs "
          "FROM songs GROUP BY name ORDER BY name COLLATE NOCASE ASC",
          readsFrom: {_db.songs},
        )
        .watch()
        .map((rows) => rows.map((row) {
              final r = row.data;
              final name = r['name'] as String;
              return AlbumModel({
                '_id': r['id'] ?? name.hashCode.abs(),
                'album': name,
                'artist': r['artist'] ?? 'Unknown Artist',
                'artist_id': r['artist_id'] ?? 0,
                'numsongs': r['numsongs'] ?? 0,
              });
            }).toList());
  }

  Stream<List<ArtistModel>> watchArtists() {
    return _db
        .customSelect(
          "SELECT MAX(artist_id) AS id, "
          "COALESCE(NULLIF(TRIM(artist),''),'Unknown Artist') AS name, "
          "COUNT(DISTINCT COALESCE(album,'')) AS albums, COUNT(*) AS tracks "
          "FROM songs GROUP BY name ORDER BY name COLLATE NOCASE ASC",
          readsFrom: {_db.songs},
        )
        .watch()
        .map((rows) => rows.map((row) {
              final r = row.data;
              final name = r['name'] as String;
              return ArtistModel({
                '_id': r['id'] ?? name.hashCode.abs(),
                'artist': name,
                'number_of_albums': r['albums'] ?? 0,
                'number_of_tracks': r['tracks'] ?? 0,
              });
            }).toList());
  }

  Stream<List<GenreModel>> watchGenres() {
    return _db
        .customSelect(
          "SELECT MAX(genre_id) AS id, "
          "COALESCE(NULLIF(TRIM(genre),''),'Unknown') AS name, "
          "COUNT(*) AS num FROM songs "
          "WHERE genre IS NOT NULL AND TRIM(genre) <> '' "
          "GROUP BY name ORDER BY name COLLATE NOCASE ASC",
          readsFrom: {_db.songs},
        )
        .watch()
        .map((rows) => rows.map((row) {
              final r = row.data;
              final name = r['name'] as String;
              return GenreModel({
                '_id': r['id'] ?? name.hashCode.abs(),
                'name': name,
                'num_of_songs': r['num'] ?? 0,
              });
            }).toList());
  }

  Stream<List<FolderEntry>> watchFolders() {
    return _db
        .customSelect(
          "SELECT folder_path AS path, COUNT(*) AS numsongs, "
          "MAX(data) AS sample, MAX(id) AS sample_id "
          "FROM songs WHERE folder_path <> '' "
          "GROUP BY folder_path ORDER BY path COLLATE NOCASE ASC",
          readsFrom: {_db.songs},
        )
        .watch()
        .map((rows) => rows.map((row) {
              final r = row.data;
              final path = r['path'] as String;
              final segs = path.split('/')..removeWhere((s) => s.isEmpty);
              return FolderEntry(
                path: path,
                name: segs.isEmpty ? path : segs.last,
                numSongs: r['numsongs'] ?? 0,
                sampleData: r['sample'] as String?,
                sampleId: r['sample_id'] as int?,
              );
            }).toList());
  }

  // ---------------------------------------------------------------------------
  // Detail song lists (filter by display name / folder — platform-stable)
  // ---------------------------------------------------------------------------

  Stream<List<SongModel>> watchAlbumSongs(String album) => _db
      .customSelect(
        "SELECT * FROM songs WHERE "
        "COALESCE(NULLIF(TRIM(album),''),'Unknown Album') = ? "
        "ORDER BY track ASC, title COLLATE NOCASE ASC",
        variables: [Variable<String>(album)],
        readsFrom: {_db.songs},
      )
      .watch()
      .map(_songs);

  Stream<List<SongModel>> watchArtistSongs(String artist) => _db
      .customSelect(
        "SELECT * FROM songs WHERE "
        "COALESCE(NULLIF(TRIM(artist),''),'Unknown Artist') = ? "
        "ORDER BY album COLLATE NOCASE ASC, track ASC, title COLLATE NOCASE ASC",
        variables: [Variable<String>(artist)],
        readsFrom: {_db.songs},
      )
      .watch()
      .map(_songs);

  Stream<List<SongModel>> watchGenreSongs(String genre) => _db
      .customSelect(
        "SELECT * FROM songs WHERE "
        "COALESCE(NULLIF(TRIM(genre),''),'Unknown') = ? "
        "ORDER BY title COLLATE NOCASE ASC",
        variables: [Variable<String>(genre)],
        readsFrom: {_db.songs},
      )
      .watch()
      .map(_songs);

  Stream<List<SongModel>> watchFolderSongs(String folderPath) => _db
      .customSelect(
        "SELECT * FROM songs WHERE folder_path = ? "
        "ORDER BY track ASC, title COLLATE NOCASE ASC",
        variables: [Variable<String>(folderPath)],
        readsFrom: {_db.songs},
      )
      .watch()
      .map(_songs);

  // ---------------------------------------------------------------------------
  // Search + discovery (read the real library, not the playback queue)
  // ---------------------------------------------------------------------------

  /// One-shot snapshots for the search page (which filters in memory).
  Future<List<AlbumModel>> albumsOnce() => watchAlbums().first;
  Future<List<ArtistModel>> artistsOnce() => watchArtists().first;
  Future<List<FolderEntry>> foldersOnce() => watchFolders().first;

  Future<List<SongModel>> searchSongs(String query, {int limit = 200}) async {
    final like = '%${query.trim()}%';
    final rows = await _db.customSelect(
      'SELECT * FROM songs WHERE title LIKE ?1 OR artist LIKE ?1 '
      'OR album LIKE ?1 ORDER BY title COLLATE NOCASE ASC LIMIT ?2',
      variables: [Variable<String>(like), Variable<int>(limit)],
    ).get();
    return _songs(rows);
  }

  /// Tracks worth considering for a station seeded on this artist/genre/album.
  ///
  /// Narrowed in SQL rather than scored in Dart over the whole library: a
  /// forty-thousand-track library would otherwise build forty thousand models
  /// on the UI isolate every time a station topped up, to keep twenty-five.
  ///
  /// [wander] is the share of the result that ignores the seed entirely. A
  /// station drawn only from exact matches can never leave the artist it
  /// started on — the scorer needs somewhere else to be able to go, even if it
  /// rarely does.
  Future<List<SongModel>> stationCandidates({
    String? artist,
    String? genre,
    String? album,
    int limit = 400,
    int wander = 100,
  }) async {
    final related = await _db.customSelect(
      'SELECT * FROM songs WHERE '
      '(?1 IS NOT NULL AND artist = ?1 COLLATE NOCASE) OR '
      '(?2 IS NOT NULL AND genre  = ?2 COLLATE NOCASE) OR '
      '(?3 IS NOT NULL AND album  = ?3 COLLATE NOCASE) '
      'ORDER BY RANDOM() LIMIT ?4',
      variables: [
        Variable<String>(_orNull(artist)),
        Variable<String>(_orNull(genre)),
        Variable<String>(_orNull(album)),
        Variable<int>(limit),
      ],
    ).get();

    final roaming = wander <= 0
        ? const <QueryRow>[]
        : await _db.customSelect(
            'SELECT * FROM songs ORDER BY RANDOM() LIMIT ?',
            variables: [Variable<int>(wander)],
          ).get();

    // De-duplicated by id: the wandering sample can legitimately land on a
    // track the narrowed query already returned.
    final byId = <Object?, SongModel>{};
    for (final row in [...related, ...roaming]) {
      byId[row.data['id']] = _song(row.data);
    }
    return byId.values.toList();
  }

  /// Blank and placeholder values read as "no constraint" rather than matching
  /// every untagged file in the library.
  static String? _orNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (const {'unknown', 'unknown artist', 'unknown album', '<unknown>'}
        .contains(trimmed.toLowerCase())) {
      return null;
    }
    return trimmed;
  }

  Future<List<SongModel>> mostPlayed({int limit = 20}) async {
    final rows = await _db.customSelect(
      'SELECT * FROM songs WHERE play_count > 0 '
      'ORDER BY play_count DESC, last_played_sec DESC LIMIT ?',
      variables: [Variable<int>(limit)],
    ).get();
    return _songs(rows);
  }

  /// Music the user owns and has barely heard.
  ///
  /// The other half of a personal home page. "Most played" tells someone what
  /// they already know; this is the shelf that can surprise them with something
  /// they chose to keep and then forgot.
  ///
  /// Ordered by how long it has been sitting there, so the oldest neglect
  /// surfaces first.
  Future<List<SongModel>> rediscover({int limit = 20}) async {
    final rows = await _db.customSelect(
      'SELECT * FROM songs WHERE play_count = 0 '
      'ORDER BY date_added ASC LIMIT ?',
      variables: [Variable<int>(limit)],
    ).get();
    return _songs(rows);
  }

  Future<List<SongModel>> recentlyAdded({int limit = 20}) async {
    final rows = await _db.customSelect(
      'SELECT * FROM songs ORDER BY date_added DESC LIMIT ?',
      variables: [Variable<int>(limit)],
    ).get();
    return _songs(rows);
  }

  // ---------------------------------------------------------------------------
  // Play counts + artwork paths
  // ---------------------------------------------------------------------------

  Future<void> incrementPlayCount(int id, int nowSec) => _db.customStatement(
        'UPDATE songs SET play_count = play_count + 1, last_played_sec = ? '
        'WHERE id = ?',
        [nowSec, id],
      );

  /// One-time import of the legacy prefs-backed play counts (song id -> count).
  Future<void> importPlayCounts(Map<int, int> counts) async {
    if (counts.isEmpty) return;
    await _db.batch((b) {
      counts.forEach((id, count) {
        b.customStatement(
            'UPDATE songs SET play_count = ? WHERE id = ?', [count, id]);
      });
    });
  }

  Future<String?> artworkPathFor(int id) async {
    final row = await _db.customSelect(
      'SELECT artwork_path FROM songs WHERE id = ? LIMIT 1',
      variables: [Variable<int>(id)],
    ).getSingleOrNull();
    return row?.data['artwork_path'] as String?;
  }

  Future<void> setArtworkPath(int id, String path) => _db.customStatement(
        'UPDATE songs SET artwork_path = ? WHERE id = ?',
        [path, id],
      );

  // ---------------------------------------------------------------------------
  // Scanner write path
  // ---------------------------------------------------------------------------

  /// Returns existing `id -> dateModified` so the scanner can diff cheaply.
  Future<Map<int, int?>> existingModifiedById() async {
    final rows = await _db
        .customSelect('SELECT id, date_modified FROM songs')
        .get();
    return {
      for (final r in rows) r.data['id'] as int: r.data['date_modified'] as int?
    };
  }

  Future<void> upsertSongs(List<SongsCompanion> rows) async {
    if (rows.isEmpty) return;
    await _db.batch((b) => b.insertAllOnConflictUpdate(_db.songs, rows));
  }

  Future<void> deleteSongs(List<int> ids) async {
    if (ids.isEmpty) return;
    await (_db.delete(_db.songs)..where((t) => t.id.isIn(ids))).go();
  }

  // ---------------------------------------------------------------------------
  // Listening history
  // ---------------------------------------------------------------------------

  /// Notes that a track was played.
  ///
  /// One insert per track change. [msPlayed] of zero is meaningful — it means
  /// the track was started and left at once, the strongest negative signal
  /// there is — so it is recorded rather than skipped.
  Future<void> recordPlayEvent({
    required int songId,
    required int atSec,
    required int msPlayed,
    required bool completed,
  }) =>
      _db.customStatement(
        'INSERT INTO play_events (song_id, at_sec, ms_played, completed) '
        'VALUES (?, ?, ?, ?)',
        [songId, atSec, msPlayed, completed ? 1 : 0],
      );

  /// Drops history older than [kPlayEventRetentionDays].
  ///
  /// [nowSec] is passed rather than read so the caller owns the clock and this
  /// stays testable.
  Future<void> prunePlayEvents(int nowSec) => _db.customStatement(
        'DELETE FROM play_events WHERE at_sec < ?',
        [nowSec - kPlayEventRetentionDays * 86400],
      );

  /// How each track has actually been listened to.
  ///
  /// Returns song id → ([plays], [skips]). A skip is a play that got less than
  /// [kSkipFraction] of the way through and did not complete; anything with no
  /// known duration cannot be judged and counts as neither.
  Future<Map<int, PlayStats>> playStats() async {
    final rows = await _db.customSelect(
      'SELECT e.song_id AS song_id, '
      '  COUNT(*) AS plays, '
      '  SUM(CASE WHEN e.completed = 0 AND s.duration IS NOT NULL '
      '           AND s.duration > 0 '
      '           AND CAST(e.ms_played AS REAL) / s.duration < ? '
      '      THEN 1 ELSE 0 END) AS skips '
      'FROM play_events e JOIN songs s ON s.id = e.song_id '
      'GROUP BY e.song_id',
      variables: [Variable<double>(kSkipFraction)],
    ).get();
    return {
      for (final row in rows)
        row.data['song_id'] as int: PlayStats(
          plays: (row.data['plays'] as num?)?.toInt() ?? 0,
          skips: (row.data['skips'] as num?)?.toInt() ?? 0,
        ),
    };
  }

  /// Which hours of the day a track tends to be played in.
  ///
  /// Returns song id → set of local hours (0-23). Used to bias a mix towards
  /// what the user actually reaches for at this time of day, which is the part
  /// that stops every day's mix being the same one.
  Future<Map<int, Set<int>>> playHours() async {
    final rows = await _db
        .customSelect(
          "SELECT song_id, CAST(strftime('%H', at_sec, 'unixepoch', 'localtime') "
          'AS INTEGER) AS hour FROM play_events GROUP BY song_id, hour',
        )
        .get();
    final out = <int, Set<int>>{};
    for (final row in rows) {
      final id = row.data['song_id'] as int;
      final hour = (row.data['hour'] as num?)?.toInt();
      if (hour == null) continue;
      (out[id] ??= <int>{}).add(hour);
    }
    return out;
  }

  Future<int> playEventCount() async {
    final row =
        await _db.customSelect('SELECT COUNT(*) AS c FROM play_events').getSingle();
    return (row.data['c'] as int?) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Playlists (app-owned)
  // ---------------------------------------------------------------------------

  Future<int> createPlaylist(String name, int nowSec) async {
    await _db.customStatement(
      'INSERT INTO playlists (name, created_sec, updated_sec) VALUES (?, ?, ?)',
      [name, nowSec, nowSec],
    );
    final row = await _db
        .customSelect('SELECT last_insert_rowid() AS id')
        .getSingle();
    return (row.data['id'] as num).toInt();
  }

  Future<List<PlaylistSummary>> playlists() async {
    final rows = await _db.customSelect(
      'SELECT p.id, p.name, p.cover_path, p.updated_sec, '
      '  (SELECT COUNT(*) FROM playlist_entries e WHERE e.playlist_id = p.id) '
      '  AS track_count '
      'FROM playlists p ORDER BY p.updated_sec DESC',
    ).get();
    return [
      for (final row in rows)
        PlaylistSummary(
          id: (row.data['id'] as num).toInt(),
          name: row.data['name'] as String? ?? '',
          coverPath: row.data['cover_path'] as String?,
          trackCount: (row.data['track_count'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  Future<void> renamePlaylist(int id, String name, int nowSec) =>
      _db.customStatement(
        'UPDATE playlists SET name = ?, updated_sec = ? WHERE id = ?',
        [name, nowSec, id],
      );

  Future<void> deletePlaylist(int id) async {
    await _db.customStatement(
      'DELETE FROM playlist_entries WHERE playlist_id = ?', [id]);
    await _db.customStatement('DELETE FROM playlists WHERE id = ?', [id]);
  }

  /// Appends [entries] to the end of a playlist, keeping positions contiguous.
  Future<void> addToPlaylist(
    int playlistId,
    List<PlaylistItem> entries,
    int nowSec,
  ) async {
    if (entries.isEmpty) return;
    final row = await _db.customSelect(
      'SELECT COALESCE(MAX(position), -1) AS last FROM playlist_entries '
      'WHERE playlist_id = ?',
      variables: [Variable<int>(playlistId)],
    ).getSingle();
    var position = ((row.data['last'] as num?)?.toInt() ?? -1) + 1;
    for (final entry in entries) {
      await _db.customStatement(
        'INSERT INTO playlist_entries '
        '(playlist_id, position, source, song_id, external_id, title, artist) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          playlistId,
          position++,
          entry.source,
          entry.songId,
          entry.externalId,
          entry.title,
          entry.artist,
        ],
      );
    }
    await _db.customStatement(
      'UPDATE playlists SET updated_sec = ? WHERE id = ?', [nowSec, playlistId]);
  }

  Future<List<PlaylistItem>> playlistEntries(int playlistId) async {
    final rows = await _db.customSelect(
      'SELECT * FROM playlist_entries WHERE playlist_id = ? ORDER BY position',
      variables: [Variable<int>(playlistId)],
    ).get();
    return [
      for (final row in rows)
        PlaylistItem(
          source: row.data['source'] as String? ?? 'local',
          songId: (row.data['song_id'] as num?)?.toInt(),
          externalId: row.data['external_id'] as String?,
          title: row.data['title'] as String? ?? '',
          artist: row.data['artist'] as String?,
        ),
    ];
  }

  Future<String?> metaGet(String key) async {
    final row = await (_db.select(_db.libraryMeta)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> metaSet(String key, String value) =>
      _db.into(_db.libraryMeta).insertOnConflictUpdate(
            LibraryMetaCompanion.insert(key: key, value: Value(value)),
          );
}
