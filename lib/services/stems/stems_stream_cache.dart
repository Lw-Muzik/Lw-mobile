/// Local copies of streamed songs, for live stems.
///
/// Stems are separated ahead of the playhead from the engine's own decode of
/// the song, and a stream the player reads from the network gives it nothing
/// to read ahead from. So while stems are in use on a YouTube Music stream,
/// the file the player streams is fetched here — the same URL, with the
/// headers it was resolved for, so the same bytes — and the engine is handed
/// the copy. It lines the copy up with what the player plays, sample for
/// sample, as it does for any file on the phone. The transfer itself is
/// [YtStreamFetch]: ranged, so it isn't held to the throttled speed of a
/// plain GET.
///
/// Copies live in the temporary directory, named by a hash of their URL; only
/// the [StemsStreamCache.keep] most recent stay (a song is 3–5 MB).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../ytmusic/yt_stream_fetch.dart';
import 'stems_model_store.dart' show StemsCancelToken, StemsDownloadCancelled;

class StemsStreamCache {
  StemsStreamCache({
    Future<Directory> Function()? directory,
    this.keep = 4,
    this.fetcher = const YtStreamFetch(),
  }) : _directory = directory ?? _defaultDirectory;

  final Future<Directory> Function() _directory;

  /// How many finished copies to keep.
  final int keep;

  /// How copies are downloaded.
  final YtStreamFetch fetcher;

  /// One transfer per URL: a second ask joins the first.
  final Map<String, Future<String>> _inFlight = {};

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getTemporaryDirectory()).path}/stems_streams');

  /// The local copy of [url], downloading it unless a finished one is here.
  ///
  /// [onProgress] gets a 0–1 fraction. Throws [StemsDownloadCancelled] once
  /// [cancel] fires, and a [YtStreamRefused] (an [HttpException]),
  /// [IOException] or [TimeoutException] when the transfer fails.
  Future<String> fetch(
    String url, {
    Map<String, String> headers = const {},
    void Function(double fraction)? onProgress,
    StemsCancelToken? cancel,
  }) {
    final running = _inFlight[url];
    if (running != null) return running;
    final job = _fetch(url, headers, onProgress, cancel);
    _inFlight[url] = job;
    return job.whenComplete(() => _inFlight.remove(url));
  }

  Future<String> _fetch(
    String url,
    Map<String, String> headers,
    void Function(double fraction)? onProgress,
    StemsCancelToken? cancel,
  ) async {
    final dir = await _directory();
    if (!dir.existsSync()) await dir.create(recursive: true);
    final target = File('${dir.path}/${fileNameFor(url)}');
    if (target.existsSync()) {
      // Most recently used, as far as pruning is concerned.
      try {
        await target.setLastModified(DateTime.now());
      } catch (_) {}
      return target.path;
    }
    final partial = File('${target.path}.part');
    try {
      await fetcher.toFile(
        Uri.parse(url),
        partial,
        headers: headers,
        onProgress: onProgress,
        cancel: cancel?.whenCancelled,
      );
      if (cancel?.isCancelled ?? false) throw const StemsDownloadCancelled();
      await partial.rename(target.path);
      unawaited(_prune(dir));
      return target.path;
    } on YtStreamFetchCancelled {
      throw const StemsDownloadCancelled();
    } finally {
      if (partial.existsSync()) {
        try {
          await partial.delete();
        } catch (_) {}
      }
    }
  }

  /// Deletes all but the [keep] most recently used copies.
  Future<void> _prune(Directory dir) async {
    try {
      final files =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => !f.path.endsWith('.part'))
              .toList()
            ..sort(
              (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
            );
      for (final f in files.skip(keep)) {
        await f.delete();
      }
    } catch (e) {
      debugPrint('Stems: could not prune stream copies: $e');
    }
  }

  /// A stable name per URL. The extension follows the stream's `mime`
  /// parameter: iOS picks its decoder by extension.
  @visibleForTesting
  static String fileNameFor(String url) {
    final hash = sha1.convert(utf8.encode(url)).toString().substring(0, 24);
    final mime = Uri.tryParse(url)?.queryParameters['mime'] ?? '';
    final ext = mime.contains('webm') ? 'webm' : 'm4a';
    return '$hash.$ext';
  }
}
