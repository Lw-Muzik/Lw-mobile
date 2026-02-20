import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:id3tag/id3tag.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../Helpers/Channel.dart';
import '../apis/index.dart';
import '../models/lyrics_model.dart';

class LyricsService {
  /// In-memory cache keyed by song ID.
  final Map<int, LyricsData> _cache = {};

  /// Resolves lyrics using the priority chain:
  /// 1. .lrc sidecar file
  /// 2. ID3 USLT tag (Dart id3tag package)
  /// 3. ID3 USLT tag (native mp3agic fallback)
  /// 4. API fetch
  Future<LyricsData?> loadLyrics(SongModel song) async {
    // Check cache first
    if (_cache.containsKey(song.id)) return _cache[song.id];

    LyricsData? result;

    final filePath = song.data;
    final isLocalFile = !filePath.startsWith('http');

    if (isLocalFile) {
      // 1. Try .lrc sidecar file
      result = await _loadFromLrcFile(filePath);

      // 2. Try ID3 USLT via Dart id3tag package
      result ??= await _loadFromId3Tag(filePath);

      // 3. Try native mp3agic fallback
      result ??= await _loadFromNative(filePath);
    }

    // 4. API fallback
    result ??= await _loadFromApi(song.title, song.artist ?? '');

    if (result != null) {
      _cache[song.id] = result;
    }
    return result;
  }

  /// Loads and parses a .lrc sidecar file next to the audio file.
  Future<LyricsData?> _loadFromLrcFile(String audioPath) async {
    try {
      final lrcPath = _lrcPathFor(audioPath);
      final file = File(lrcPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          return parseLrc(content);
        }
      }
    } catch (e) {
      debugPrint('LyricsService: error reading .lrc file: $e');
    }
    return null;
  }

  /// Reads USLT frame from ID3 tag using the Dart id3tag package.
  Future<LyricsData?> _loadFromId3Tag(String filePath) async {
    try {
      final parser = ID3TagReader.path(filePath);
      final tag = await parser.readTag();
      final lyricsList = tag.lyrics;
      if (lyricsList.isNotEmpty) {
        final text = lyricsList.first.lyrics;
        if (text.isNotEmpty) {
          return parseLrc(text);
        }
      }
    } catch (e) {
      debugPrint('LyricsService: error reading ID3 lyrics: $e');
    }
    return null;
  }

  /// Native mp3agic fallback for reading embedded lyrics.
  Future<LyricsData?> _loadFromNative(String filePath) async {
    try {
      final text = await Channel.readLyrics(filePath);
      if (text != null && text.isNotEmpty) {
        return parseLrc(text);
      }
    } catch (e) {
      debugPrint('LyricsService: error reading native lyrics: $e');
    }
    return null;
  }

  /// Fetches lyrics from the backend API.
  Future<LyricsData?> _loadFromApi(String title, String artist) async {
    try {
      final text = await Apis.fetchLyricsData(title, artist);
      if (text != null && text.isNotEmpty) {
        return parseLrc(text);
      }
    } catch (e) {
      debugPrint('LyricsService: error fetching lyrics from API: $e');
    }
    return null;
  }

  /// Saves lyrics to a .lrc sidecar file next to the audio file.
  Future<bool> saveLyricsToLrc(SongModel song, LyricsData lyrics) async {
    try {
      final lrcPath = _lrcPathFor(song.data);
      final file = File(lrcPath);
      await file.writeAsString(encodeLrc(lyrics));
      _cache[song.id] = lyrics;
      return true;
    } catch (e) {
      debugPrint('LyricsService: error saving .lrc file: $e');
      return false;
    }
  }

  /// Embeds lyrics text into the MP3 file's ID3 USLT tag via native channel.
  Future<bool> saveLyricsToId3(SongModel song, String lyricsText) async {
    try {
      return await Channel.writeLyrics(song.data, lyricsText);
    } catch (e) {
      debugPrint('LyricsService: error writing ID3 lyrics: $e');
      return false;
    }
  }

  /// Clears the cache entry for a specific song (e.g. after editing lyrics).
  void invalidateCache(int songId) {
    _cache.remove(songId);
  }

  /// Clears the entire lyrics cache.
  void clearCache() {
    _cache.clear();
  }

  /// Computes the .lrc file path for an audio file.
  String _lrcPathFor(String audioPath) {
    final lastDot = audioPath.lastIndexOf('.');
    final basePath = lastDot > 0 ? audioPath.substring(0, lastDot) : audioPath;
    return '$basePath.lrc';
  }
}
