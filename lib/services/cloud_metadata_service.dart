import 'dart:developer' as dev;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:id3tag/id3tag.dart';
import 'package:path_provider/path_provider.dart';

import '../models/cloud_file.dart';
import 'cloud_auth_service.dart';
import 'cloud_cache_service.dart';
import 'dropbox_service.dart';
import 'google_drive_service.dart';

/// Background service that preloads ID3 metadata (title, artist, album, artwork)
/// for all cloud files. Downloads the first 512KB of each file to parse tags.
class CloudMetadataService {
  final CloudAuthService _auth;
  final CloudCacheService _cache;
  final GoogleDriveService _gdrive;
  final DropboxService _dropbox;

  /// Max concurrent extractions to avoid hammering APIs.
  static const _maxConcurrent = 3;

  /// Track active runs per provider so we can cancel on disconnect.
  int _gdriveRunId = 0;
  int _dropboxRunId = 0;

  CloudMetadataService(this._auth, this._cache, this._gdrive, this._dropbox);

  /// Cancel any running preload for a specific provider (or all).
  void cancel([CloudProvider? provider]) {
    if (provider == null || provider == CloudProvider.googleDrive) {
      _gdriveRunId++;
    }
    if (provider == null || provider == CloudProvider.dropbox) {
      _dropboxRunId++;
    }
  }

  /// Preload ID3 metadata for all [files] of a given [provider].
  /// Skips files that already have a `.done` marker (previously extracted).
  /// Processes [_maxConcurrent] files concurrently.
  Future<void> preloadAll(
      CloudProvider provider, List<CloudFile> files) async {
    // Bump run ID to invalidate any previous run for this provider.
    final runId = provider == CloudProvider.googleDrive
        ? ++_gdriveRunId
        : ++_dropboxRunId;

    final tempDir = await getTemporaryDirectory();

    // Filter to files that haven't been extracted yet.
    final pending = <CloudFile>[];
    for (final file in files) {
      final songId = file.fileId.hashCode.abs();
      final markerPath = '${tempDir.path}/cloud_meta_$songId.done';
      if (!File(markerPath).existsSync()) {
        pending.add(file);
      }
    }

    if (pending.isEmpty) {
      dev.log(
        'All ${files.length} files already have metadata',
        name: 'CloudMeta',
      );
      return;
    }

    dev.log(
      'Preloading metadata: ${pending.length}/${files.length} '
      '(${provider.name})',
      name: 'CloudMeta',
    );

    // Process in batches of _maxConcurrent.
    for (int i = 0; i < pending.length; i += _maxConcurrent) {
      // Check if this run was superseded or cancelled.
      if (!_isRunActive(provider, runId)) return;

      final end = (i + _maxConcurrent).clamp(0, pending.length);
      final batch = pending.sublist(i, end);

      await Future.wait(
        batch.map((file) => _extractSingle(file, tempDir, provider, runId)),
      );
    }

    dev.log('Metadata preload complete (${provider.name})', name: 'CloudMeta');
  }

  bool _isRunActive(CloudProvider provider, int runId) {
    return provider == CloudProvider.googleDrive
        ? runId == _gdriveRunId
        : runId == _dropboxRunId;
  }

  Future<void> _extractSingle(
    CloudFile file,
    Directory tempDir,
    CloudProvider provider,
    int runId,
  ) async {
    final songId = file.fileId.hashCode.abs();
    final artPath = '${tempDir.path}/cloud_art_$songId.png';
    final metaCachePath = '${tempDir.path}/cloud_meta_$songId.done';

    // Double-check marker (could have been created by concurrent run).
    if (File(metaCachePath).existsSync()) return;

    try {
      // Resolve stream URL.
      String? streamUrl;
      if (provider == CloudProvider.googleDrive) {
        streamUrl = _gdrive.getStreamUrl(file.fileId);
      } else {
        streamUrl = await _dropbox.getTemporaryLink(file.fileId);
      }
      if (streamUrl == null) return;

      // Check cancellation before network call.
      if (!_isRunActive(provider, runId)) return;

      // Build headers (Google Drive needs auth; Dropbox temp links don't).
      final headers = <String, String>{};
      if (provider == CloudProvider.googleDrive) {
        headers.addAll(await _auth.getGoogleAuthHeaders());
      }
      headers['Range'] = 'bytes=0-524287'; // First 512 KB

      final response = await http.get(Uri.parse(streamUrl), headers: headers);
      if (response.statusCode != 200 && response.statusCode != 206) return;

      if (!_isRunActive(provider, runId)) return;

      final partialPath = '${tempDir.path}/cloud_partial_$songId.tmp';
      final partialFile = File(partialPath);
      await partialFile.writeAsBytes(response.bodyBytes);

      // Parse ID3 tags.
      String? title, artist, album;

      try {
        final parser = ID3TagReader.path(partialPath);
        final tag = await parser.readTag();

        final titleFrames = tag.framesWithName('TIT2');
        if (titleFrames.isNotEmpty && titleFrames.first is TextInformation) {
          title = (titleFrames.first as TextInformation).value;
        }
        final artistFrames = tag.framesWithName('TPE1');
        if (artistFrames.isNotEmpty &&
            artistFrames.first is TextInformation) {
          artist = (artistFrames.first as TextInformation).value;
        }
        final albumFrames = tag.framesWithName('TALB');
        if (albumFrames.isNotEmpty &&
            albumFrames.first is TextInformation) {
          album = (albumFrames.first as TextInformation).value;
        }

        if (tag.pictures.isNotEmpty) {
          await File(artPath).writeAsBytes(tag.pictures.first.imageData);
        }
      } catch (_) {}

      // Clean up partial download.
      if (partialFile.existsSync()) partialFile.deleteSync();

      // Write completion marker.
      await File(metaCachePath).writeAsString('done');

      // Persist extracted metadata to the cached file list.
      if (title != null || artist != null || album != null) {
        final updated = CloudFile(
          provider: file.provider,
          fileId: file.fileId,
          name: file.name,
          folderPath: file.folderPath,
          size: file.size,
          mimeType: file.mimeType,
          thumbnailUrl: file.thumbnailUrl,
          modifiedDate: file.modifiedDate,
          trackTitle: title ?? file.trackTitle,
          trackArtist: artist ?? file.trackArtist,
          albumName: album ?? file.albumName,
          durationMs: file.durationMs,
        );
        _cache.updateFileMetadata(provider, updated);
      }
    } catch (e) {
      dev.log(
        'Metadata extract failed for ${file.name}: $e',
        name: 'CloudMeta',
      );
    }
  }
}
