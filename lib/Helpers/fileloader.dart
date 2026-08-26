import 'dart:convert';
import 'package:flutter/foundation.dart';
import '/helpers/index.dart';
import '/controllers/player_controller.dart';
import '/exports/exports.dart';
import '/services/local_music_scanner.dart';

class MetadataCache {
  final Set<String> processedIds;
  final Map<String, List<dynamic>> modelCache;

  MetadataCache(this.processedIds, this.modelCache);

  static Future<MetadataCache> initialize(SharedPreferences prefs) async {
    final processedFiles = prefs.getStringList("processedFileIds");
    final modelKeys = ["allSongs", "genres", "albums", "artists"];

    if (processedFiles == null ||
        modelKeys.any((key) => prefs.getString(key) == null)) {
      // Initialize empty cache
      for (var key in modelKeys) {
        await prefs.setString(key, json.encode([]));
      }
      await prefs.setStringList("processedFileIds", []);
      return MetadataCache({}, {for (var key in modelKeys) key: []});
    }

    return MetadataCache(processedFiles.toSet(), {
      for (var key in modelKeys) key: json.decode(prefs.getString(key) ?? "[]"),
    });
  }
}

class MetadataProcessor {
  final BuildContext context;
  final PlayerController controller;
  final SharedPreferences prefs;
  final MetadataCache cache;
  final OnAudioQuery audioQuery;
  static const int batchSize = 10;

  MetadataProcessor(this.context, this.controller, this.prefs, this.cache)
    : audioQuery = OnAudioQuery();

  Future<void> _processBatch<T>(
    String modelKey,
    List<T> items,
    Future<void> Function(T item) processItem,
  ) async {
    final batches = (items.length / batchSize).ceil();

    for (var i = 0; i < batches; i++) {
      final start = i * batchSize;
      final end = (start + batchSize < items.length)
          ? start + batchSize
          : items.length;

      await Future.wait(
        items.sublist(start, end).map((item) => processItem(item)),
      );

      // Save progress periodically
      if (i % 5 == 0 || i == batches - 1) {
        await prefs.setStringList(
          "processedFileIds",
          cache.processedIds.toList(),
        );
        for (var key in cache.modelCache.keys) {
          await prefs.setString(key, json.encode(cache.modelCache[key]));
        }
      }
    }
  }

  Future<void> processArtists() async {
    List<ArtistModel> artists;
    try {
      artists = await audioQuery.queryArtists();
    } catch (_) {
      artists = [];
    }

    // On iOS, if MPMediaQuery returned nothing, derive artists from local songs
    if (artists.isEmpty && defaultTargetPlatform == TargetPlatform.iOS) {
      final localSongs = await LocalMusicScanner.scanLocalFiles();
      final artistMap = <String, int>{};
      for (final s in localSongs) {
        final name = s.artist ?? 'Unknown Artist';
        artistMap[name] = (artistMap[name] ?? 0) + 1;
      }
      for (final entry in artistMap.entries) {
        final id = entry.key.hashCode.abs();
        if (!cache.processedIds.contains(id.toString())) {
          cache.processedIds.add(id.toString());
          cache.modelCache["artists"]?.add({
            "_id": id,
            "artist": entry.key,
            "number_of_albums": 0,
            "number_of_tracks": entry.value,
          });
        }
      }
      if (artistMap.isNotEmpty) controller.textHeader = "Processing artists";
      return;
    }

    if (artists.isEmpty) return;
    controller.textHeader = "Processing artists";
    await _processBatch<ArtistModel>(
      "artists",
      artists
          .where((a) => !cache.processedIds.contains(a.id.toString()))
          .toList(),
      (artist) async {
        await fetchArtwork(
          "",
          artist.id,
          type: ArtworkType.ARTIST,
          other: artist.getMap['artist'] ?? 'Unknown',
        );
        controller.text = artist.getMap['artist'] ?? 'Unknown';
        cache.processedIds.add(artist.id.toString());
        cache.modelCache["artists"]?.add(artist.getMap);
      },
    );
  }

  Future<void> processAlbums() async {
    List<AlbumModel> albums;
    try {
      albums = await audioQuery.queryAlbums();
    } catch (_) {
      albums = [];
    }

    // On iOS, derive albums from local songs
    if (albums.isEmpty && defaultTargetPlatform == TargetPlatform.iOS) {
      final localSongs = await LocalMusicScanner.scanLocalFiles();
      final albumMap = <String, Map<String, dynamic>>{};
      for (final s in localSongs) {
        final name = (s.album != null && s.album!.isNotEmpty)
            ? s.album!
            : 'Unknown Album';
        albumMap.putIfAbsent(
          name,
          () => {
            "_id": name.hashCode.abs(),
            "album": name,
            "artist": s.artist ?? 'Unknown Artist',
            "number_of_songs": 0,
          },
        );
        albumMap[name]!["number_of_songs"] =
            (albumMap[name]!["number_of_songs"] as int) + 1;
      }
      for (final entry in albumMap.values) {
        final id = entry["_id"].toString();
        if (!cache.processedIds.contains(id)) {
          cache.processedIds.add(id);
          cache.modelCache["albums"]?.add(entry);
        }
      }
      return;
    }

    if (albums.isEmpty) return;
    controller.textHeader = "Processing albums";
    await _processBatch<AlbumModel>(
      "albums",
      albums
          .where((a) => !cache.processedIds.contains(a.id.toString()))
          .toList(),
      (album) async {
        await fetchArtwork(
          "",
          album.id,
          type: ArtworkType.ALBUM,
          other: album.getMap['album'] ?? 'Unknown',
        );
        controller.text = album.getMap['album'] ?? 'Unknown';
        cache.processedIds.add(album.id.toString());
        cache.modelCache["albums"]?.add(album.getMap);
      },
    );
  }

  Future<void> processGenres() async {
    List<GenreModel> genres;
    try {
      genres = await audioQuery.queryGenres();
    } catch (_) {
      genres = [];
    }

    // On iOS, derive genres from local songs (skip — genre metadata rarely in local files)
    if (genres.isEmpty) return;

    controller.textHeader = "Processing genres";
    await _processBatch<GenreModel>(
      "genres",
      genres
          .where((g) => !cache.processedIds.contains(g.id.toString()))
          .toList(),
      (genre) async {
        await fetchArtwork(
          "",
          genre.id,
          type: ArtworkType.GENRE,
          other: genre.genre,
        );
        controller.text = genre.genre;
        cache.processedIds.add(genre.id.toString());
        cache.modelCache["genres"]?.add(genre.getMap);
      },
    );
  }

  Future<void> processSongs() async {
    List<SongModel> songs;
    try {
      songs = await audioQuery.querySongs();
    } catch (_) {
      songs = [];
    }

    // On iOS, also scan the local Documents/Music directory for imported files
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final localSongs = await LocalMusicScanner.scanLocalFiles();
        if (localSongs.isNotEmpty) {
          // Merge: avoid duplicates by path
          final existingPaths = songs.map((s) => s.data).toSet();
          final newLocal = localSongs.where(
            (s) => !existingPaths.contains(s.data),
          );
          songs = [...songs, ...newLocal];
        }
      } catch (e) {
        debugPrint('LocalMusicScanner error: $e');
      }
    }

    if (songs.isEmpty) return;

    controller.textHeader = "Processing songs";
    await _processBatch<SongModel>(
      "allSongs",
      songs
          .where((s) => !cache.processedIds.contains(s.id.toString()))
          .toList(),
      (song) async {
        await fetchArtwork(song.data, song.id, type: ArtworkType.AUDIO);
        controller.text = song.title;
        cache.processedIds.add(song.id.toString());
        cache.modelCache["allSongs"]?.add(song.getMap);
      },
    );
  }
}

Future<String> fetchMetaData(BuildContext context) async {
  final controller = Provider.of<PlayerController>(context, listen: false);
  final prefs = await SharedPreferences.getInstance();
  final cache = await MetadataCache.initialize(prefs);
  final processor = MetadataProcessor(context, controller, prefs, cache);

  try {
    // On iOS, verify media library permission before querying.
    // on_audio_query uses MPMediaQuery which requires explicit authorization.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final hasPermission = await processor.audioQuery.permissionsStatus();
      if (!hasPermission) {
        final granted = await processor.audioQuery.permissionsRequest();
        if (!granted) {
          controller.textHeader = "";
          controller.text =
              "Music library access denied.\nGrant access in Settings > Hype Muzik.";
          return controller.text;
        }
      }
    }

    await processor.processArtists();
    await processor.processAlbums();
    await processor.processGenres();
    await processor.processSongs();

    controller.textHeader = "";
    controller.text = "All files assembled\nEnjoy.....";
    return controller.text;
  } catch (e) {
    controller.textHeader = "Error";
    controller.text = "Failed to process some files";
    return "Error: $e";
  }
}
