import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CloudCacheService {
  final SharedPreferences _prefs;
  late Directory _cacheDir;
  Map<String, _CacheEntry> _metadata = {};

  static const _metadataKey = 'cloud_cache_metadata';
  static const int defaultMaxCacheBytes = 500 * 1024 * 1024; // 500 MB

  int get maxCacheBytes =>
      _prefs.getInt('cloudCacheMaxBytes') ?? defaultMaxCacheBytes;

  set maxCacheBytes(int value) {
    _prefs.setInt('cloudCacheMaxBytes', value);
  }

  CloudCacheService(this._prefs);

  Future<void> init() async {
    final appDir = await getApplicationSupportDirectory();
    _cacheDir = Directory('${appDir.path}/cloud_audio_cache');
    if (!_cacheDir.existsSync()) {
      _cacheDir.createSync(recursive: true);
    }
    _loadMetadata();
  }

  File cacheFile(String fileId) {
    final hash = fileId.hashCode.toRadixString(16);
    return File('${_cacheDir.path}/$hash.audio');
  }

  bool isCached(String fileId) {
    final entry = _metadata[fileId];
    if (entry == null || !entry.complete) return false;
    return cacheFile(fileId).existsSync();
  }

  Future<void> preCacheTrack(
      String url, String fileId, Map<String, String> headers) async {
    if (isCached(fileId)) return;

    final file = cacheFile(fileId);
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(headers);

      final client = http.Client();
      final response = await client.send(request);

      if (response.statusCode == 200) {
        final sink = file.openWrite();
        await response.stream.pipe(sink);
        await sink.flush();
        await sink.close();

        final stat = file.statSync();
        _metadata[fileId] = _CacheEntry(
          size: stat.size,
          lastAccess: DateTime.now(),
          complete: true,
        );
        _saveMetadata();
        await _evictIfNeeded();
      }
      client.close();
    } catch (_) {
      // Clean up partial file
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
    }
  }

  void markAccessed(String fileId) {
    final entry = _metadata[fileId];
    if (entry != null) {
      _metadata[fileId] = _CacheEntry(
        size: entry.size,
        lastAccess: DateTime.now(),
        complete: entry.complete,
      );
      _saveMetadata();
    }
  }

  int get currentSize {
    int total = 0;
    for (final entry in _metadata.values) {
      if (entry.complete) total += entry.size;
    }
    return total;
  }

  String get currentSizeFormatted {
    final bytes = currentSize;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> clearCache() async {
    if (_cacheDir.existsSync()) {
      await _cacheDir.delete(recursive: true);
      await _cacheDir.create(recursive: true);
    }
    _metadata.clear();
    _saveMetadata();
  }

  Future<void> _evictIfNeeded() async {
    while (currentSize > maxCacheBytes && _metadata.isNotEmpty) {
      // Find LRU entry
      String? lruId;
      DateTime? oldest;
      for (final entry in _metadata.entries) {
        if (oldest == null || entry.value.lastAccess.isBefore(oldest)) {
          oldest = entry.value.lastAccess;
          lruId = entry.key;
        }
      }
      if (lruId == null) break;

      final file = cacheFile(lruId);
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
      _metadata.remove(lruId);
    }
    _saveMetadata();
  }

  void _loadMetadata() {
    final raw = _prefs.getString(_metadataKey);
    if (raw != null) {
      try {
        final map = json.decode(raw) as Map<String, dynamic>;
        _metadata = map.map((k, v) => MapEntry(k, _CacheEntry.fromJson(v)));
      } catch (_) {
        _metadata = {};
      }
    }
  }

  void _saveMetadata() {
    _prefs.setString(
      _metadataKey,
      json.encode(_metadata.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }
}

class _CacheEntry {
  final int size;
  final DateTime lastAccess;
  final bool complete;

  _CacheEntry({
    required this.size,
    required this.lastAccess,
    required this.complete,
  });

  Map<String, dynamic> toJson() => {
        'size': size,
        'lastAccess': lastAccess.toIso8601String(),
        'complete': complete,
      };

  factory _CacheEntry.fromJson(Map<String, dynamic> json) => _CacheEntry(
        size: json['size'] as int,
        lastAccess: DateTime.parse(json['lastAccess'] as String),
        complete: json['complete'] as bool,
      );
}
