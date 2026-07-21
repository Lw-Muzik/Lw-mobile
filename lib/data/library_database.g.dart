// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_database.dart';

// ignore_for_file: type=lint
class $SongsTable extends Songs with TableInfo<$SongsTable, Song> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SongsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uriMeta = const VerificationMeta('uri');
  @override
  late final GeneratedColumn<String> uri = GeneratedColumn<String>(
    'uri',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _displayNameWOExtMeta = const VerificationMeta(
    'displayNameWOExt',
  );
  @override
  late final GeneratedColumn<String> displayNameWOExt = GeneratedColumn<String>(
    'display_name_w_o_ext',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumIdMeta = const VerificationMeta(
    'albumId',
  );
  @override
  late final GeneratedColumn<int> albumId = GeneratedColumn<int>(
    'album_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artistIdMeta = const VerificationMeta(
    'artistId',
  );
  @override
  late final GeneratedColumn<int> artistId = GeneratedColumn<int>(
    'artist_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genreMeta = const VerificationMeta('genre');
  @override
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
    'genre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genreIdMeta = const VerificationMeta(
    'genreId',
  );
  @override
  late final GeneratedColumn<int> genreId = GeneratedColumn<int>(
    'genre_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _composerMeta = const VerificationMeta(
    'composer',
  );
  @override
  late final GeneratedColumn<String> composer = GeneratedColumn<String>(
    'composer',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateAddedMeta = const VerificationMeta(
    'dateAdded',
  );
  @override
  late final GeneratedColumn<int> dateAdded = GeneratedColumn<int>(
    'date_added',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateModifiedMeta = const VerificationMeta(
    'dateModified',
  );
  @override
  late final GeneratedColumn<int> dateModified = GeneratedColumn<int>(
    'date_modified',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMeta = const VerificationMeta(
    'duration',
  );
  @override
  late final GeneratedColumn<int> duration = GeneratedColumn<int>(
    'duration',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _trackMeta = const VerificationMeta('track');
  @override
  late final GeneratedColumn<int> track = GeneratedColumn<int>(
    'track',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileExtensionMeta = const VerificationMeta(
    'fileExtension',
  );
  @override
  late final GeneratedColumn<String> fileExtension = GeneratedColumn<String>(
    'file_extension',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _folderPathMeta = const VerificationMeta(
    'folderPath',
  );
  @override
  late final GeneratedColumn<String> folderPath = GeneratedColumn<String>(
    'folder_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _artworkPathMeta = const VerificationMeta(
    'artworkPath',
  );
  @override
  late final GeneratedColumn<String> artworkPath = GeneratedColumn<String>(
    'artwork_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _playCountMeta = const VerificationMeta(
    'playCount',
  );
  @override
  late final GeneratedColumn<int> playCount = GeneratedColumn<int>(
    'play_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastPlayedSecMeta = const VerificationMeta(
    'lastPlayedSec',
  );
  @override
  late final GeneratedColumn<int> lastPlayedSec = GeneratedColumn<int>(
    'last_played_sec',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    data,
    uri,
    displayName,
    displayNameWOExt,
    size,
    album,
    albumId,
    artist,
    artistId,
    genre,
    genreId,
    composer,
    dateAdded,
    dateModified,
    duration,
    title,
    track,
    fileExtension,
    folderPath,
    artworkPath,
    playCount,
    lastPlayedSec,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'songs';
  @override
  VerificationContext validateIntegrity(
    Insertable<Song> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    if (data.containsKey('uri')) {
      context.handle(
        _uriMeta,
        uri.isAcceptableOrUnknown(data['uri']!, _uriMeta),
      );
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('display_name_w_o_ext')) {
      context.handle(
        _displayNameWOExtMeta,
        displayNameWOExt.isAcceptableOrUnknown(
          data['display_name_w_o_ext']!,
          _displayNameWOExtMeta,
        ),
      );
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    }
    if (data.containsKey('album_id')) {
      context.handle(
        _albumIdMeta,
        albumId.isAcceptableOrUnknown(data['album_id']!, _albumIdMeta),
      );
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    }
    if (data.containsKey('artist_id')) {
      context.handle(
        _artistIdMeta,
        artistId.isAcceptableOrUnknown(data['artist_id']!, _artistIdMeta),
      );
    }
    if (data.containsKey('genre')) {
      context.handle(
        _genreMeta,
        genre.isAcceptableOrUnknown(data['genre']!, _genreMeta),
      );
    }
    if (data.containsKey('genre_id')) {
      context.handle(
        _genreIdMeta,
        genreId.isAcceptableOrUnknown(data['genre_id']!, _genreIdMeta),
      );
    }
    if (data.containsKey('composer')) {
      context.handle(
        _composerMeta,
        composer.isAcceptableOrUnknown(data['composer']!, _composerMeta),
      );
    }
    if (data.containsKey('date_added')) {
      context.handle(
        _dateAddedMeta,
        dateAdded.isAcceptableOrUnknown(data['date_added']!, _dateAddedMeta),
      );
    }
    if (data.containsKey('date_modified')) {
      context.handle(
        _dateModifiedMeta,
        dateModified.isAcceptableOrUnknown(
          data['date_modified']!,
          _dateModifiedMeta,
        ),
      );
    }
    if (data.containsKey('duration')) {
      context.handle(
        _durationMeta,
        duration.isAcceptableOrUnknown(data['duration']!, _durationMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('track')) {
      context.handle(
        _trackMeta,
        track.isAcceptableOrUnknown(data['track']!, _trackMeta),
      );
    }
    if (data.containsKey('file_extension')) {
      context.handle(
        _fileExtensionMeta,
        fileExtension.isAcceptableOrUnknown(
          data['file_extension']!,
          _fileExtensionMeta,
        ),
      );
    }
    if (data.containsKey('folder_path')) {
      context.handle(
        _folderPathMeta,
        folderPath.isAcceptableOrUnknown(data['folder_path']!, _folderPathMeta),
      );
    }
    if (data.containsKey('artwork_path')) {
      context.handle(
        _artworkPathMeta,
        artworkPath.isAcceptableOrUnknown(
          data['artwork_path']!,
          _artworkPathMeta,
        ),
      );
    }
    if (data.containsKey('play_count')) {
      context.handle(
        _playCountMeta,
        playCount.isAcceptableOrUnknown(data['play_count']!, _playCountMeta),
      );
    }
    if (data.containsKey('last_played_sec')) {
      context.handle(
        _lastPlayedSecMeta,
        lastPlayedSec.isAcceptableOrUnknown(
          data['last_played_sec']!,
          _lastPlayedSecMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Song map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Song(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
      uri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uri'],
      ),
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      displayNameWOExt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name_w_o_ext'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      ),
      albumId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}album_id'],
      ),
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      ),
      artistId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}artist_id'],
      ),
      genre: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre'],
      ),
      genreId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}genre_id'],
      ),
      composer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}composer'],
      ),
      dateAdded: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date_added'],
      ),
      dateModified: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date_modified'],
      ),
      duration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      track: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}track'],
      ),
      fileExtension: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_extension'],
      )!,
      folderPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder_path'],
      )!,
      artworkPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artwork_path'],
      ),
      playCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}play_count'],
      )!,
      lastPlayedSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_played_sec'],
      ),
    );
  }

  @override
  $SongsTable createAlias(String alias) {
    return $SongsTable(attachedDatabase, alias);
  }
}

class Song extends DataClass implements Insertable<Song> {
  /// MediaStore `_id`. Stable per file, so it doubles as our primary key and
  /// the diff key alongside [dateModified].
  final int id;
  final String data;
  final String? uri;
  final String displayName;
  final String displayNameWOExt;
  final int size;
  final String? album;
  final int? albumId;
  final String? artist;
  final int? artistId;
  final String? genre;
  final int? genreId;
  final String? composer;
  final int? dateAdded;
  final int? dateModified;
  final int? duration;
  final String title;
  final int? track;
  final String fileExtension;

  /// Parent directory of [data] (everything up to the last `/`). Derived once
  /// at insert time so the Folders tab is a `GROUP BY`, not a per-card scan.
  final String folderPath;

  /// Path to the on-disk extracted artwork PNG, filled lazily by
  /// `ArtworkService` the first time a tile becomes visible. Null = not yet
  /// resolved (never blocks the scan).
  final String? artworkPath;
  final int playCount;
  final int? lastPlayedSec;
  const Song({
    required this.id,
    required this.data,
    this.uri,
    required this.displayName,
    required this.displayNameWOExt,
    required this.size,
    this.album,
    this.albumId,
    this.artist,
    this.artistId,
    this.genre,
    this.genreId,
    this.composer,
    this.dateAdded,
    this.dateModified,
    this.duration,
    required this.title,
    this.track,
    required this.fileExtension,
    required this.folderPath,
    this.artworkPath,
    required this.playCount,
    this.lastPlayedSec,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['data'] = Variable<String>(data);
    if (!nullToAbsent || uri != null) {
      map['uri'] = Variable<String>(uri);
    }
    map['display_name'] = Variable<String>(displayName);
    map['display_name_w_o_ext'] = Variable<String>(displayNameWOExt);
    map['size'] = Variable<int>(size);
    if (!nullToAbsent || album != null) {
      map['album'] = Variable<String>(album);
    }
    if (!nullToAbsent || albumId != null) {
      map['album_id'] = Variable<int>(albumId);
    }
    if (!nullToAbsent || artist != null) {
      map['artist'] = Variable<String>(artist);
    }
    if (!nullToAbsent || artistId != null) {
      map['artist_id'] = Variable<int>(artistId);
    }
    if (!nullToAbsent || genre != null) {
      map['genre'] = Variable<String>(genre);
    }
    if (!nullToAbsent || genreId != null) {
      map['genre_id'] = Variable<int>(genreId);
    }
    if (!nullToAbsent || composer != null) {
      map['composer'] = Variable<String>(composer);
    }
    if (!nullToAbsent || dateAdded != null) {
      map['date_added'] = Variable<int>(dateAdded);
    }
    if (!nullToAbsent || dateModified != null) {
      map['date_modified'] = Variable<int>(dateModified);
    }
    if (!nullToAbsent || duration != null) {
      map['duration'] = Variable<int>(duration);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || track != null) {
      map['track'] = Variable<int>(track);
    }
    map['file_extension'] = Variable<String>(fileExtension);
    map['folder_path'] = Variable<String>(folderPath);
    if (!nullToAbsent || artworkPath != null) {
      map['artwork_path'] = Variable<String>(artworkPath);
    }
    map['play_count'] = Variable<int>(playCount);
    if (!nullToAbsent || lastPlayedSec != null) {
      map['last_played_sec'] = Variable<int>(lastPlayedSec);
    }
    return map;
  }

  SongsCompanion toCompanion(bool nullToAbsent) {
    return SongsCompanion(
      id: Value(id),
      data: Value(data),
      uri: uri == null && nullToAbsent ? const Value.absent() : Value(uri),
      displayName: Value(displayName),
      displayNameWOExt: Value(displayNameWOExt),
      size: Value(size),
      album: album == null && nullToAbsent
          ? const Value.absent()
          : Value(album),
      albumId: albumId == null && nullToAbsent
          ? const Value.absent()
          : Value(albumId),
      artist: artist == null && nullToAbsent
          ? const Value.absent()
          : Value(artist),
      artistId: artistId == null && nullToAbsent
          ? const Value.absent()
          : Value(artistId),
      genre: genre == null && nullToAbsent
          ? const Value.absent()
          : Value(genre),
      genreId: genreId == null && nullToAbsent
          ? const Value.absent()
          : Value(genreId),
      composer: composer == null && nullToAbsent
          ? const Value.absent()
          : Value(composer),
      dateAdded: dateAdded == null && nullToAbsent
          ? const Value.absent()
          : Value(dateAdded),
      dateModified: dateModified == null && nullToAbsent
          ? const Value.absent()
          : Value(dateModified),
      duration: duration == null && nullToAbsent
          ? const Value.absent()
          : Value(duration),
      title: Value(title),
      track: track == null && nullToAbsent
          ? const Value.absent()
          : Value(track),
      fileExtension: Value(fileExtension),
      folderPath: Value(folderPath),
      artworkPath: artworkPath == null && nullToAbsent
          ? const Value.absent()
          : Value(artworkPath),
      playCount: Value(playCount),
      lastPlayedSec: lastPlayedSec == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPlayedSec),
    );
  }

  factory Song.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Song(
      id: serializer.fromJson<int>(json['id']),
      data: serializer.fromJson<String>(json['data']),
      uri: serializer.fromJson<String?>(json['uri']),
      displayName: serializer.fromJson<String>(json['displayName']),
      displayNameWOExt: serializer.fromJson<String>(json['displayNameWOExt']),
      size: serializer.fromJson<int>(json['size']),
      album: serializer.fromJson<String?>(json['album']),
      albumId: serializer.fromJson<int?>(json['albumId']),
      artist: serializer.fromJson<String?>(json['artist']),
      artistId: serializer.fromJson<int?>(json['artistId']),
      genre: serializer.fromJson<String?>(json['genre']),
      genreId: serializer.fromJson<int?>(json['genreId']),
      composer: serializer.fromJson<String?>(json['composer']),
      dateAdded: serializer.fromJson<int?>(json['dateAdded']),
      dateModified: serializer.fromJson<int?>(json['dateModified']),
      duration: serializer.fromJson<int?>(json['duration']),
      title: serializer.fromJson<String>(json['title']),
      track: serializer.fromJson<int?>(json['track']),
      fileExtension: serializer.fromJson<String>(json['fileExtension']),
      folderPath: serializer.fromJson<String>(json['folderPath']),
      artworkPath: serializer.fromJson<String?>(json['artworkPath']),
      playCount: serializer.fromJson<int>(json['playCount']),
      lastPlayedSec: serializer.fromJson<int?>(json['lastPlayedSec']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'data': serializer.toJson<String>(data),
      'uri': serializer.toJson<String?>(uri),
      'displayName': serializer.toJson<String>(displayName),
      'displayNameWOExt': serializer.toJson<String>(displayNameWOExt),
      'size': serializer.toJson<int>(size),
      'album': serializer.toJson<String?>(album),
      'albumId': serializer.toJson<int?>(albumId),
      'artist': serializer.toJson<String?>(artist),
      'artistId': serializer.toJson<int?>(artistId),
      'genre': serializer.toJson<String?>(genre),
      'genreId': serializer.toJson<int?>(genreId),
      'composer': serializer.toJson<String?>(composer),
      'dateAdded': serializer.toJson<int?>(dateAdded),
      'dateModified': serializer.toJson<int?>(dateModified),
      'duration': serializer.toJson<int?>(duration),
      'title': serializer.toJson<String>(title),
      'track': serializer.toJson<int?>(track),
      'fileExtension': serializer.toJson<String>(fileExtension),
      'folderPath': serializer.toJson<String>(folderPath),
      'artworkPath': serializer.toJson<String?>(artworkPath),
      'playCount': serializer.toJson<int>(playCount),
      'lastPlayedSec': serializer.toJson<int?>(lastPlayedSec),
    };
  }

  Song copyWith({
    int? id,
    String? data,
    Value<String?> uri = const Value.absent(),
    String? displayName,
    String? displayNameWOExt,
    int? size,
    Value<String?> album = const Value.absent(),
    Value<int?> albumId = const Value.absent(),
    Value<String?> artist = const Value.absent(),
    Value<int?> artistId = const Value.absent(),
    Value<String?> genre = const Value.absent(),
    Value<int?> genreId = const Value.absent(),
    Value<String?> composer = const Value.absent(),
    Value<int?> dateAdded = const Value.absent(),
    Value<int?> dateModified = const Value.absent(),
    Value<int?> duration = const Value.absent(),
    String? title,
    Value<int?> track = const Value.absent(),
    String? fileExtension,
    String? folderPath,
    Value<String?> artworkPath = const Value.absent(),
    int? playCount,
    Value<int?> lastPlayedSec = const Value.absent(),
  }) => Song(
    id: id ?? this.id,
    data: data ?? this.data,
    uri: uri.present ? uri.value : this.uri,
    displayName: displayName ?? this.displayName,
    displayNameWOExt: displayNameWOExt ?? this.displayNameWOExt,
    size: size ?? this.size,
    album: album.present ? album.value : this.album,
    albumId: albumId.present ? albumId.value : this.albumId,
    artist: artist.present ? artist.value : this.artist,
    artistId: artistId.present ? artistId.value : this.artistId,
    genre: genre.present ? genre.value : this.genre,
    genreId: genreId.present ? genreId.value : this.genreId,
    composer: composer.present ? composer.value : this.composer,
    dateAdded: dateAdded.present ? dateAdded.value : this.dateAdded,
    dateModified: dateModified.present ? dateModified.value : this.dateModified,
    duration: duration.present ? duration.value : this.duration,
    title: title ?? this.title,
    track: track.present ? track.value : this.track,
    fileExtension: fileExtension ?? this.fileExtension,
    folderPath: folderPath ?? this.folderPath,
    artworkPath: artworkPath.present ? artworkPath.value : this.artworkPath,
    playCount: playCount ?? this.playCount,
    lastPlayedSec: lastPlayedSec.present
        ? lastPlayedSec.value
        : this.lastPlayedSec,
  );
  Song copyWithCompanion(SongsCompanion data) {
    return Song(
      id: data.id.present ? data.id.value : this.id,
      data: data.data.present ? data.data.value : this.data,
      uri: data.uri.present ? data.uri.value : this.uri,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      displayNameWOExt: data.displayNameWOExt.present
          ? data.displayNameWOExt.value
          : this.displayNameWOExt,
      size: data.size.present ? data.size.value : this.size,
      album: data.album.present ? data.album.value : this.album,
      albumId: data.albumId.present ? data.albumId.value : this.albumId,
      artist: data.artist.present ? data.artist.value : this.artist,
      artistId: data.artistId.present ? data.artistId.value : this.artistId,
      genre: data.genre.present ? data.genre.value : this.genre,
      genreId: data.genreId.present ? data.genreId.value : this.genreId,
      composer: data.composer.present ? data.composer.value : this.composer,
      dateAdded: data.dateAdded.present ? data.dateAdded.value : this.dateAdded,
      dateModified: data.dateModified.present
          ? data.dateModified.value
          : this.dateModified,
      duration: data.duration.present ? data.duration.value : this.duration,
      title: data.title.present ? data.title.value : this.title,
      track: data.track.present ? data.track.value : this.track,
      fileExtension: data.fileExtension.present
          ? data.fileExtension.value
          : this.fileExtension,
      folderPath: data.folderPath.present
          ? data.folderPath.value
          : this.folderPath,
      artworkPath: data.artworkPath.present
          ? data.artworkPath.value
          : this.artworkPath,
      playCount: data.playCount.present ? data.playCount.value : this.playCount,
      lastPlayedSec: data.lastPlayedSec.present
          ? data.lastPlayedSec.value
          : this.lastPlayedSec,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Song(')
          ..write('id: $id, ')
          ..write('data: $data, ')
          ..write('uri: $uri, ')
          ..write('displayName: $displayName, ')
          ..write('displayNameWOExt: $displayNameWOExt, ')
          ..write('size: $size, ')
          ..write('album: $album, ')
          ..write('albumId: $albumId, ')
          ..write('artist: $artist, ')
          ..write('artistId: $artistId, ')
          ..write('genre: $genre, ')
          ..write('genreId: $genreId, ')
          ..write('composer: $composer, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('dateModified: $dateModified, ')
          ..write('duration: $duration, ')
          ..write('title: $title, ')
          ..write('track: $track, ')
          ..write('fileExtension: $fileExtension, ')
          ..write('folderPath: $folderPath, ')
          ..write('artworkPath: $artworkPath, ')
          ..write('playCount: $playCount, ')
          ..write('lastPlayedSec: $lastPlayedSec')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    data,
    uri,
    displayName,
    displayNameWOExt,
    size,
    album,
    albumId,
    artist,
    artistId,
    genre,
    genreId,
    composer,
    dateAdded,
    dateModified,
    duration,
    title,
    track,
    fileExtension,
    folderPath,
    artworkPath,
    playCount,
    lastPlayedSec,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Song &&
          other.id == this.id &&
          other.data == this.data &&
          other.uri == this.uri &&
          other.displayName == this.displayName &&
          other.displayNameWOExt == this.displayNameWOExt &&
          other.size == this.size &&
          other.album == this.album &&
          other.albumId == this.albumId &&
          other.artist == this.artist &&
          other.artistId == this.artistId &&
          other.genre == this.genre &&
          other.genreId == this.genreId &&
          other.composer == this.composer &&
          other.dateAdded == this.dateAdded &&
          other.dateModified == this.dateModified &&
          other.duration == this.duration &&
          other.title == this.title &&
          other.track == this.track &&
          other.fileExtension == this.fileExtension &&
          other.folderPath == this.folderPath &&
          other.artworkPath == this.artworkPath &&
          other.playCount == this.playCount &&
          other.lastPlayedSec == this.lastPlayedSec);
}

class SongsCompanion extends UpdateCompanion<Song> {
  final Value<int> id;
  final Value<String> data;
  final Value<String?> uri;
  final Value<String> displayName;
  final Value<String> displayNameWOExt;
  final Value<int> size;
  final Value<String?> album;
  final Value<int?> albumId;
  final Value<String?> artist;
  final Value<int?> artistId;
  final Value<String?> genre;
  final Value<int?> genreId;
  final Value<String?> composer;
  final Value<int?> dateAdded;
  final Value<int?> dateModified;
  final Value<int?> duration;
  final Value<String> title;
  final Value<int?> track;
  final Value<String> fileExtension;
  final Value<String> folderPath;
  final Value<String?> artworkPath;
  final Value<int> playCount;
  final Value<int?> lastPlayedSec;
  const SongsCompanion({
    this.id = const Value.absent(),
    this.data = const Value.absent(),
    this.uri = const Value.absent(),
    this.displayName = const Value.absent(),
    this.displayNameWOExt = const Value.absent(),
    this.size = const Value.absent(),
    this.album = const Value.absent(),
    this.albumId = const Value.absent(),
    this.artist = const Value.absent(),
    this.artistId = const Value.absent(),
    this.genre = const Value.absent(),
    this.genreId = const Value.absent(),
    this.composer = const Value.absent(),
    this.dateAdded = const Value.absent(),
    this.dateModified = const Value.absent(),
    this.duration = const Value.absent(),
    this.title = const Value.absent(),
    this.track = const Value.absent(),
    this.fileExtension = const Value.absent(),
    this.folderPath = const Value.absent(),
    this.artworkPath = const Value.absent(),
    this.playCount = const Value.absent(),
    this.lastPlayedSec = const Value.absent(),
  });
  SongsCompanion.insert({
    this.id = const Value.absent(),
    required String data,
    this.uri = const Value.absent(),
    this.displayName = const Value.absent(),
    this.displayNameWOExt = const Value.absent(),
    this.size = const Value.absent(),
    this.album = const Value.absent(),
    this.albumId = const Value.absent(),
    this.artist = const Value.absent(),
    this.artistId = const Value.absent(),
    this.genre = const Value.absent(),
    this.genreId = const Value.absent(),
    this.composer = const Value.absent(),
    this.dateAdded = const Value.absent(),
    this.dateModified = const Value.absent(),
    this.duration = const Value.absent(),
    this.title = const Value.absent(),
    this.track = const Value.absent(),
    this.fileExtension = const Value.absent(),
    this.folderPath = const Value.absent(),
    this.artworkPath = const Value.absent(),
    this.playCount = const Value.absent(),
    this.lastPlayedSec = const Value.absent(),
  }) : data = Value(data);
  static Insertable<Song> custom({
    Expression<int>? id,
    Expression<String>? data,
    Expression<String>? uri,
    Expression<String>? displayName,
    Expression<String>? displayNameWOExt,
    Expression<int>? size,
    Expression<String>? album,
    Expression<int>? albumId,
    Expression<String>? artist,
    Expression<int>? artistId,
    Expression<String>? genre,
    Expression<int>? genreId,
    Expression<String>? composer,
    Expression<int>? dateAdded,
    Expression<int>? dateModified,
    Expression<int>? duration,
    Expression<String>? title,
    Expression<int>? track,
    Expression<String>? fileExtension,
    Expression<String>? folderPath,
    Expression<String>? artworkPath,
    Expression<int>? playCount,
    Expression<int>? lastPlayedSec,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (data != null) 'data': data,
      if (uri != null) 'uri': uri,
      if (displayName != null) 'display_name': displayName,
      if (displayNameWOExt != null) 'display_name_w_o_ext': displayNameWOExt,
      if (size != null) 'size': size,
      if (album != null) 'album': album,
      if (albumId != null) 'album_id': albumId,
      if (artist != null) 'artist': artist,
      if (artistId != null) 'artist_id': artistId,
      if (genre != null) 'genre': genre,
      if (genreId != null) 'genre_id': genreId,
      if (composer != null) 'composer': composer,
      if (dateAdded != null) 'date_added': dateAdded,
      if (dateModified != null) 'date_modified': dateModified,
      if (duration != null) 'duration': duration,
      if (title != null) 'title': title,
      if (track != null) 'track': track,
      if (fileExtension != null) 'file_extension': fileExtension,
      if (folderPath != null) 'folder_path': folderPath,
      if (artworkPath != null) 'artwork_path': artworkPath,
      if (playCount != null) 'play_count': playCount,
      if (lastPlayedSec != null) 'last_played_sec': lastPlayedSec,
    });
  }

  SongsCompanion copyWith({
    Value<int>? id,
    Value<String>? data,
    Value<String?>? uri,
    Value<String>? displayName,
    Value<String>? displayNameWOExt,
    Value<int>? size,
    Value<String?>? album,
    Value<int?>? albumId,
    Value<String?>? artist,
    Value<int?>? artistId,
    Value<String?>? genre,
    Value<int?>? genreId,
    Value<String?>? composer,
    Value<int?>? dateAdded,
    Value<int?>? dateModified,
    Value<int?>? duration,
    Value<String>? title,
    Value<int?>? track,
    Value<String>? fileExtension,
    Value<String>? folderPath,
    Value<String?>? artworkPath,
    Value<int>? playCount,
    Value<int?>? lastPlayedSec,
  }) {
    return SongsCompanion(
      id: id ?? this.id,
      data: data ?? this.data,
      uri: uri ?? this.uri,
      displayName: displayName ?? this.displayName,
      displayNameWOExt: displayNameWOExt ?? this.displayNameWOExt,
      size: size ?? this.size,
      album: album ?? this.album,
      albumId: albumId ?? this.albumId,
      artist: artist ?? this.artist,
      artistId: artistId ?? this.artistId,
      genre: genre ?? this.genre,
      genreId: genreId ?? this.genreId,
      composer: composer ?? this.composer,
      dateAdded: dateAdded ?? this.dateAdded,
      dateModified: dateModified ?? this.dateModified,
      duration: duration ?? this.duration,
      title: title ?? this.title,
      track: track ?? this.track,
      fileExtension: fileExtension ?? this.fileExtension,
      folderPath: folderPath ?? this.folderPath,
      artworkPath: artworkPath ?? this.artworkPath,
      playCount: playCount ?? this.playCount,
      lastPlayedSec: lastPlayedSec ?? this.lastPlayedSec,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (uri.present) {
      map['uri'] = Variable<String>(uri.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (displayNameWOExt.present) {
      map['display_name_w_o_ext'] = Variable<String>(displayNameWOExt.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (albumId.present) {
      map['album_id'] = Variable<int>(albumId.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (artistId.present) {
      map['artist_id'] = Variable<int>(artistId.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (genreId.present) {
      map['genre_id'] = Variable<int>(genreId.value);
    }
    if (composer.present) {
      map['composer'] = Variable<String>(composer.value);
    }
    if (dateAdded.present) {
      map['date_added'] = Variable<int>(dateAdded.value);
    }
    if (dateModified.present) {
      map['date_modified'] = Variable<int>(dateModified.value);
    }
    if (duration.present) {
      map['duration'] = Variable<int>(duration.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (track.present) {
      map['track'] = Variable<int>(track.value);
    }
    if (fileExtension.present) {
      map['file_extension'] = Variable<String>(fileExtension.value);
    }
    if (folderPath.present) {
      map['folder_path'] = Variable<String>(folderPath.value);
    }
    if (artworkPath.present) {
      map['artwork_path'] = Variable<String>(artworkPath.value);
    }
    if (playCount.present) {
      map['play_count'] = Variable<int>(playCount.value);
    }
    if (lastPlayedSec.present) {
      map['last_played_sec'] = Variable<int>(lastPlayedSec.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SongsCompanion(')
          ..write('id: $id, ')
          ..write('data: $data, ')
          ..write('uri: $uri, ')
          ..write('displayName: $displayName, ')
          ..write('displayNameWOExt: $displayNameWOExt, ')
          ..write('size: $size, ')
          ..write('album: $album, ')
          ..write('albumId: $albumId, ')
          ..write('artist: $artist, ')
          ..write('artistId: $artistId, ')
          ..write('genre: $genre, ')
          ..write('genreId: $genreId, ')
          ..write('composer: $composer, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('dateModified: $dateModified, ')
          ..write('duration: $duration, ')
          ..write('title: $title, ')
          ..write('track: $track, ')
          ..write('fileExtension: $fileExtension, ')
          ..write('folderPath: $folderPath, ')
          ..write('artworkPath: $artworkPath, ')
          ..write('playCount: $playCount, ')
          ..write('lastPlayedSec: $lastPlayedSec')
          ..write(')'))
        .toString();
  }
}

class $LibraryMetaTable extends LibraryMeta
    with TableInfo<$LibraryMetaTable, LibraryMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LibraryMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<LibraryMetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  LibraryMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryMetaData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      ),
    );
  }

  @override
  $LibraryMetaTable createAlias(String alias) {
    return $LibraryMetaTable(attachedDatabase, alias);
  }
}

class LibraryMetaData extends DataClass implements Insertable<LibraryMetaData> {
  final String key;
  final String? value;
  const LibraryMetaData({required this.key, this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    if (!nullToAbsent || value != null) {
      map['value'] = Variable<String>(value);
    }
    return map;
  }

  LibraryMetaCompanion toCompanion(bool nullToAbsent) {
    return LibraryMetaCompanion(
      key: Value(key),
      value: value == null && nullToAbsent
          ? const Value.absent()
          : Value(value),
    );
  }

  factory LibraryMetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryMetaData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String?>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String?>(value),
    };
  }

  LibraryMetaData copyWith({
    String? key,
    Value<String?> value = const Value.absent(),
  }) => LibraryMetaData(
    key: key ?? this.key,
    value: value.present ? value.value : this.value,
  );
  LibraryMetaData copyWithCompanion(LibraryMetaCompanion data) {
    return LibraryMetaData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryMetaData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibraryMetaData &&
          other.key == this.key &&
          other.value == this.value);
}

class LibraryMetaCompanion extends UpdateCompanion<LibraryMetaData> {
  final Value<String> key;
  final Value<String?> value;
  final Value<int> rowid;
  const LibraryMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LibraryMetaCompanion.insert({
    required String key,
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key);
  static Insertable<LibraryMetaData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LibraryMetaCompanion copyWith({
    Value<String>? key,
    Value<String?>? value,
    Value<int>? rowid,
  }) {
    return LibraryMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LibraryMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LibraryDatabase extends GeneratedDatabase {
  _$LibraryDatabase(QueryExecutor e) : super(e);
  $LibraryDatabaseManager get managers => $LibraryDatabaseManager(this);
  late final $SongsTable songs = $SongsTable(this);
  late final $LibraryMetaTable libraryMeta = $LibraryMetaTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [songs, libraryMeta];
}

typedef $$SongsTableCreateCompanionBuilder =
    SongsCompanion Function({
      Value<int> id,
      required String data,
      Value<String?> uri,
      Value<String> displayName,
      Value<String> displayNameWOExt,
      Value<int> size,
      Value<String?> album,
      Value<int?> albumId,
      Value<String?> artist,
      Value<int?> artistId,
      Value<String?> genre,
      Value<int?> genreId,
      Value<String?> composer,
      Value<int?> dateAdded,
      Value<int?> dateModified,
      Value<int?> duration,
      Value<String> title,
      Value<int?> track,
      Value<String> fileExtension,
      Value<String> folderPath,
      Value<String?> artworkPath,
      Value<int> playCount,
      Value<int?> lastPlayedSec,
    });
typedef $$SongsTableUpdateCompanionBuilder =
    SongsCompanion Function({
      Value<int> id,
      Value<String> data,
      Value<String?> uri,
      Value<String> displayName,
      Value<String> displayNameWOExt,
      Value<int> size,
      Value<String?> album,
      Value<int?> albumId,
      Value<String?> artist,
      Value<int?> artistId,
      Value<String?> genre,
      Value<int?> genreId,
      Value<String?> composer,
      Value<int?> dateAdded,
      Value<int?> dateModified,
      Value<int?> duration,
      Value<String> title,
      Value<int?> track,
      Value<String> fileExtension,
      Value<String> folderPath,
      Value<String?> artworkPath,
      Value<int> playCount,
      Value<int?> lastPlayedSec,
    });

class $$SongsTableFilterComposer
    extends Composer<_$LibraryDatabase, $SongsTable> {
  $$SongsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uri => $composableBuilder(
    column: $table.uri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayNameWOExt => $composableBuilder(
    column: $table.displayNameWOExt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get artistId => $composableBuilder(
    column: $table.artistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get genreId => $composableBuilder(
    column: $table.genreId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get composer => $composableBuilder(
    column: $table.composer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateModified => $composableBuilder(
    column: $table.dateModified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get duration => $composableBuilder(
    column: $table.duration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get track => $composableBuilder(
    column: $table.track,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileExtension => $composableBuilder(
    column: $table.fileExtension,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get folderPath => $composableBuilder(
    column: $table.folderPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artworkPath => $composableBuilder(
    column: $table.artworkPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastPlayedSec => $composableBuilder(
    column: $table.lastPlayedSec,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SongsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $SongsTable> {
  $$SongsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uri => $composableBuilder(
    column: $table.uri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayNameWOExt => $composableBuilder(
    column: $table.displayNameWOExt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get artistId => $composableBuilder(
    column: $table.artistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get genreId => $composableBuilder(
    column: $table.genreId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get composer => $composableBuilder(
    column: $table.composer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateModified => $composableBuilder(
    column: $table.dateModified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get duration => $composableBuilder(
    column: $table.duration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get track => $composableBuilder(
    column: $table.track,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileExtension => $composableBuilder(
    column: $table.fileExtension,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get folderPath => $composableBuilder(
    column: $table.folderPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artworkPath => $composableBuilder(
    column: $table.artworkPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastPlayedSec => $composableBuilder(
    column: $table.lastPlayedSec,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SongsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $SongsTable> {
  $$SongsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<String> get uri =>
      $composableBuilder(column: $table.uri, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayNameWOExt => $composableBuilder(
    column: $table.displayNameWOExt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<int> get albumId =>
      $composableBuilder(column: $table.albumId, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<int> get artistId =>
      $composableBuilder(column: $table.artistId, builder: (column) => column);

  GeneratedColumn<String> get genre =>
      $composableBuilder(column: $table.genre, builder: (column) => column);

  GeneratedColumn<int> get genreId =>
      $composableBuilder(column: $table.genreId, builder: (column) => column);

  GeneratedColumn<String> get composer =>
      $composableBuilder(column: $table.composer, builder: (column) => column);

  GeneratedColumn<int> get dateAdded =>
      $composableBuilder(column: $table.dateAdded, builder: (column) => column);

  GeneratedColumn<int> get dateModified => $composableBuilder(
    column: $table.dateModified,
    builder: (column) => column,
  );

  GeneratedColumn<int> get duration =>
      $composableBuilder(column: $table.duration, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get track =>
      $composableBuilder(column: $table.track, builder: (column) => column);

  GeneratedColumn<String> get fileExtension => $composableBuilder(
    column: $table.fileExtension,
    builder: (column) => column,
  );

  GeneratedColumn<String> get folderPath => $composableBuilder(
    column: $table.folderPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get artworkPath => $composableBuilder(
    column: $table.artworkPath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get playCount =>
      $composableBuilder(column: $table.playCount, builder: (column) => column);

  GeneratedColumn<int> get lastPlayedSec => $composableBuilder(
    column: $table.lastPlayedSec,
    builder: (column) => column,
  );
}

class $$SongsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $SongsTable,
          Song,
          $$SongsTableFilterComposer,
          $$SongsTableOrderingComposer,
          $$SongsTableAnnotationComposer,
          $$SongsTableCreateCompanionBuilder,
          $$SongsTableUpdateCompanionBuilder,
          (Song, BaseReferences<_$LibraryDatabase, $SongsTable, Song>),
          Song,
          PrefetchHooks Function()
        > {
  $$SongsTableTableManager(_$LibraryDatabase db, $SongsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SongsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SongsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SongsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> data = const Value.absent(),
                Value<String?> uri = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> displayNameWOExt = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<int?> albumId = const Value.absent(),
                Value<String?> artist = const Value.absent(),
                Value<int?> artistId = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<int?> genreId = const Value.absent(),
                Value<String?> composer = const Value.absent(),
                Value<int?> dateAdded = const Value.absent(),
                Value<int?> dateModified = const Value.absent(),
                Value<int?> duration = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int?> track = const Value.absent(),
                Value<String> fileExtension = const Value.absent(),
                Value<String> folderPath = const Value.absent(),
                Value<String?> artworkPath = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<int?> lastPlayedSec = const Value.absent(),
              }) => SongsCompanion(
                id: id,
                data: data,
                uri: uri,
                displayName: displayName,
                displayNameWOExt: displayNameWOExt,
                size: size,
                album: album,
                albumId: albumId,
                artist: artist,
                artistId: artistId,
                genre: genre,
                genreId: genreId,
                composer: composer,
                dateAdded: dateAdded,
                dateModified: dateModified,
                duration: duration,
                title: title,
                track: track,
                fileExtension: fileExtension,
                folderPath: folderPath,
                artworkPath: artworkPath,
                playCount: playCount,
                lastPlayedSec: lastPlayedSec,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String data,
                Value<String?> uri = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> displayNameWOExt = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<int?> albumId = const Value.absent(),
                Value<String?> artist = const Value.absent(),
                Value<int?> artistId = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<int?> genreId = const Value.absent(),
                Value<String?> composer = const Value.absent(),
                Value<int?> dateAdded = const Value.absent(),
                Value<int?> dateModified = const Value.absent(),
                Value<int?> duration = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int?> track = const Value.absent(),
                Value<String> fileExtension = const Value.absent(),
                Value<String> folderPath = const Value.absent(),
                Value<String?> artworkPath = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<int?> lastPlayedSec = const Value.absent(),
              }) => SongsCompanion.insert(
                id: id,
                data: data,
                uri: uri,
                displayName: displayName,
                displayNameWOExt: displayNameWOExt,
                size: size,
                album: album,
                albumId: albumId,
                artist: artist,
                artistId: artistId,
                genre: genre,
                genreId: genreId,
                composer: composer,
                dateAdded: dateAdded,
                dateModified: dateModified,
                duration: duration,
                title: title,
                track: track,
                fileExtension: fileExtension,
                folderPath: folderPath,
                artworkPath: artworkPath,
                playCount: playCount,
                lastPlayedSec: lastPlayedSec,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SongsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $SongsTable,
      Song,
      $$SongsTableFilterComposer,
      $$SongsTableOrderingComposer,
      $$SongsTableAnnotationComposer,
      $$SongsTableCreateCompanionBuilder,
      $$SongsTableUpdateCompanionBuilder,
      (Song, BaseReferences<_$LibraryDatabase, $SongsTable, Song>),
      Song,
      PrefetchHooks Function()
    >;
typedef $$LibraryMetaTableCreateCompanionBuilder =
    LibraryMetaCompanion Function({
      required String key,
      Value<String?> value,
      Value<int> rowid,
    });
typedef $$LibraryMetaTableUpdateCompanionBuilder =
    LibraryMetaCompanion Function({
      Value<String> key,
      Value<String?> value,
      Value<int> rowid,
    });

class $$LibraryMetaTableFilterComposer
    extends Composer<_$LibraryDatabase, $LibraryMetaTable> {
  $$LibraryMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LibraryMetaTableOrderingComposer
    extends Composer<_$LibraryDatabase, $LibraryMetaTable> {
  $$LibraryMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LibraryMetaTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $LibraryMetaTable> {
  $$LibraryMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$LibraryMetaTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $LibraryMetaTable,
          LibraryMetaData,
          $$LibraryMetaTableFilterComposer,
          $$LibraryMetaTableOrderingComposer,
          $$LibraryMetaTableAnnotationComposer,
          $$LibraryMetaTableCreateCompanionBuilder,
          $$LibraryMetaTableUpdateCompanionBuilder,
          (
            LibraryMetaData,
            BaseReferences<
              _$LibraryDatabase,
              $LibraryMetaTable,
              LibraryMetaData
            >,
          ),
          LibraryMetaData,
          PrefetchHooks Function()
        > {
  $$LibraryMetaTableTableManager(_$LibraryDatabase db, $LibraryMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LibraryMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LibraryMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LibraryMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String?> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LibraryMetaCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                Value<String?> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LibraryMetaCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LibraryMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $LibraryMetaTable,
      LibraryMetaData,
      $$LibraryMetaTableFilterComposer,
      $$LibraryMetaTableOrderingComposer,
      $$LibraryMetaTableAnnotationComposer,
      $$LibraryMetaTableCreateCompanionBuilder,
      $$LibraryMetaTableUpdateCompanionBuilder,
      (
        LibraryMetaData,
        BaseReferences<_$LibraryDatabase, $LibraryMetaTable, LibraryMetaData>,
      ),
      LibraryMetaData,
      PrefetchHooks Function()
    >;

class $LibraryDatabaseManager {
  final _$LibraryDatabase _db;
  $LibraryDatabaseManager(this._db);
  $$SongsTableTableManager get songs =>
      $$SongsTableTableManager(_db, _db.songs);
  $$LibraryMetaTableTableManager get libraryMeta =>
      $$LibraryMetaTableTableManager(_db, _db.libraryMeta);
}
