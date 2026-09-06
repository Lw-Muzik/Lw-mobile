/// Saving a YouTube track to the phone's own music library.
///
/// The stream this downloads is the same itag 140 the player streams — an m4a
/// AAC file — so a download is the track, not a transcode of it.
///
/// On Android the file is handed to [NativeMediaStore] rather than written into
/// the shared music tree directly: the app targets SDK 36 and is fully under
/// scoped storage, where inserting a `MediaStore.Audio.Media` row is the only
/// sanctioned way in. That insert doubles as the registration, so a downloaded
/// track appears in the app's own Library with no separate scan.
///
/// On iOS there is no equivalent: `MPMediaLibrary` will not accept an arbitrary
/// file, so the track goes to `Documents/Music` — the directory
/// [LocalMusicScanner] walks and merges into the library, and which
/// `UIFileSharingEnabled` also exposes in Files. Both platforms therefore end
/// with the track in the app's Library; only the mechanism differs.
library;

import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../local_music_scanner.dart';
import '../native_media_store.dart';
import 'yt_models.dart';
import 'yt_repository.dart';

/// How a download ended.
sealed class YtDownloadResult {
  const YtDownloadResult();
}

class YtDownloadSaved extends YtDownloadResult {
  /// Where the track ended up, as the phone will report it.
  final String path;

  /// Whether it was published to the shared music library, as opposed to
  /// staying inside the app.
  final bool inLibrary;

  const YtDownloadSaved(this.path, {required this.inLibrary});
}

class YtDownloadFailed extends YtDownloadResult {
  final String message;
  const YtDownloadFailed(this.message);
}

class YtDownloader {
  const YtDownloader._();

  /// Downloads one track.
  ///
  /// [onProgress] is called with a 0–1 fraction where the server states a
  /// length, and never called where it doesn't — a fake progress bar is worse
  /// than none.
  static Future<YtDownloadResult> download(
    YtTrack track, {
    void Function(double fraction)? onProgress,
  }) async {
    HttpClient? client;
    File? partial;
    try {
      final target = await YtMusicRepository.instance.audioTarget(
        track.videoId,
      );

      // Android stages in app documents and publishes to MediaStore below.
      // iOS has nowhere to publish to, so it writes straight into the one
      // directory the library actually scans — writing to the Documents root
      // instead would leave the track invisible until something else happened
      // to rescan.
      final directory = Platform.isIOS
          ? await LocalMusicScanner.getMusicDirectory()
          : await getApplicationDocumentsDirectory();
      final name = _fileName(track);
      // Downloaded to a `.part` first so a cancelled or failed transfer can
      // never be mistaken for a complete track — by this app or by MediaStore.
      partial = File('${directory.path}/$name.part');
      final sink = partial.openWrite();

      client = HttpClient();
      final request = await client.getUrl(Uri.parse(target.url));
      target.headers.forEach(request.headers.set);
      final response = await request.close();
      if (response.statusCode != 200) {
        await sink.close();
        await partial.delete();
        // A dead URL is worth forgetting: the retry should ask YouTube again
        // rather than replay the same expired target.
        YtMusicRepository.instance.forget(track.videoId);
        return YtDownloadFailed('Download failed (${response.statusCode}).');
      }

      final total = response.contentLength;
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
      await sink.close();

      final finished = File('${directory.path}/$name.m4a');
      await partial.rename(finished.path);
      partial = null;

      if (NativeMediaStore.supported) {
        final row = await NativeMediaStore.importAudio(
          sourcePath: finished.path,
          displayName: '$name.m4a',
          mimeType: 'audio/mp4',
        );
        if (row != null) {
          // The MediaStore row owns the file now; the app copy is a duplicate.
          await _deleteQuietly(finished);
          return YtDownloadSaved(
            (row['path'] as String?) ?? finished.path,
            inLibrary: true,
          );
        }
      }
      return YtDownloadSaved(finished.path, inLibrary: false);
    } on YtException catch (e) {
      return YtDownloadFailed(e.message);
    } catch (e) {
      return YtDownloadFailed('Download failed: $e');
    } finally {
      client?.close(force: true);
      if (partial != null) await _deleteQuietly(partial);
    }
  }

  /// Downloads a whole list, one track at a time.
  ///
  /// # Why sequential
  ///
  /// Each track needs its own resolved stream URL, and resolving is the part
  /// YouTube rate-limits. Downloading four at once turns one slow playlist into
  /// four failed ones, and the bytes arrive no faster on a phone's connection
  /// anyway. [onTrack] reports `(index, total, title)` as each begins so the
  /// caller can say which one, and [onProgress] is that track's own fraction.
  ///
  /// A failure does not stop the run: one dead video should not cost the other
  /// forty-nine. The returned list is per-track and in order, so the caller can
  /// say exactly how many landed.
  static Future<List<YtDownloadResult>> downloadAll(
    List<YtTrack> tracks, {
    void Function(int index, int total, String title)? onTrack,
    void Function(double fraction)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final results = <YtDownloadResult>[];
    for (var i = 0; i < tracks.length; i++) {
      if (isCancelled?.call() ?? false) break;
      final track = tracks[i];
      onTrack?.call(i, tracks.length, track.title);
      results.add(await download(track, onProgress: onProgress));
    }
    return results;
  }

  /// A file name that survives every filesystem this app runs on.
  ///
  /// Keeps the track identifiable while dropping anything a path separator or a
  /// Windows-hostile character could turn into a different file than intended.
  static String _fileName(YtTrack track) {
    final artist = track.artist;
    final raw = artist == null || artist.isEmpty
        ? track.title
        : '$artist - ${track.title}';
    final cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return track.videoId;
    // Long names are rejected outright by some filesystems, so cap well short
    // of any real limit and keep the id as the tiebreaker.
    return cleaned.length <= 80 ? cleaned : cleaned.substring(0, 80).trim();
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // A leftover temp file is not worth failing a finished download over.
    }
  }
}
