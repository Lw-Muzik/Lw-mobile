/// Local copies of streamed songs, for live stems.
///
/// Stems are separated ahead of the playhead from the engine's own decode of
/// the song, and a stream the player reads from the network gives it nothing
/// to read ahead from. So while stems are in use on a YouTube Music stream,
/// the file the player streams is fetched here — the same URL, with the
/// headers it was resolved for, so the same bytes — and the engine is handed
/// the copy. It lines the copy up with what the player plays, sample for
/// sample, as it does for any file on the phone.
///
/// # In ranges
///
/// googlevideo throttles one plain GET of a stream to about twice its bitrate
/// — ~31 KB/s for itag 140, a minute and a half for a song (measured Oct
/// 2026) — but serves 256 KB range requests at full speed: a whole song in
/// about 3 s over a few connections. Smaller ranges trip the throttle on some
/// requests, and even at this size one in a few dozen stalls, so a range that
/// takes longer than [StemsStreamCache.chunkTimeout] is dropped and asked
/// again.
///
/// Copies live in the temporary directory, named by a hash of their URL; only
/// the [StemsStreamCache.keep] most recent stay (a song is 3–5 MB).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'stems_model_store.dart' show StemsCancelToken, StemsDownloadCancelled;

class StemsStreamCache {
  StemsStreamCache({
    Future<Directory> Function()? directory,
    HttpClient Function()? httpClient,
    this.keep = 4,
    this.chunkBytes = 256 * 1024,
    this.parallel = 3,
    this.chunkTimeout = const Duration(seconds: 4),
    this.chunkAttempts = 4,
  }) : _directory = directory ?? _defaultDirectory,
       _httpClient = httpClient ?? HttpClient.new;

  final Future<Directory> Function() _directory;
  final HttpClient Function() _httpClient;

  /// How many finished copies to keep.
  final int keep;

  /// Bytes per range request.
  final int chunkBytes;

  /// Range requests in flight at once.
  final int parallel;

  /// A range that hasn't arrived whole in this long was throttled: it is
  /// dropped and asked for again, up to [chunkAttempts] times.
  final Duration chunkTimeout;
  final int chunkAttempts;

  /// One transfer per URL: a second ask joins the first.
  final Map<String, Future<String>> _inFlight = {};

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getTemporaryDirectory()).path}/stems_streams');

  /// The local copy of [url], downloading it unless a finished one is here.
  ///
  /// [onProgress] gets a 0–1 fraction. Throws [StemsDownloadCancelled] once
  /// [cancel] fires, and an [HttpException], [IOException] or
  /// [TimeoutException] when the transfer fails.
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
    final transfer = _Transfer(this, Uri.parse(url), headers, cancel);
    try {
      await transfer.run(partial, onProgress);
      if (cancel?.isCancelled ?? false) throw const StemsDownloadCancelled();
      await partial.rename(target.path);
      unawaited(_prune(dir));
      return target.path;
    } catch (e) {
      // A transfer closed by the cancel shows up as a socket error.
      if (cancel?.isCancelled ?? false) throw const StemsDownloadCancelled();
      rethrow;
    } finally {
      transfer.closeAll();
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

/// One download: the first range finds the size (or that the server ignores
/// ranges), then a few workers take the remaining ranges in turn.
class _Transfer {
  _Transfer(this.cache, this.uri, this.headers, this.cancel) {
    cancel?.whenCancelled.then((_) => closeAll());
  }

  final StemsStreamCache cache;
  final Uri uri;
  final Map<String, String> headers;
  final StemsCancelToken? cancel;
  final Set<HttpClient> _clients = {};
  bool _closed = false;

  HttpClient _open() {
    if (_closed) throw const StemsDownloadCancelled();
    final c = cache._httpClient();
    _clients.add(c);
    return c;
  }

  void _drop(HttpClient c) {
    _clients.remove(c);
    c.close(force: true);
  }

  void closeAll() {
    _closed = true;
    for (final c in _clients.toList()) {
      c.close(force: true);
    }
    _clients.clear();
  }

  void _checkCancelled() {
    if ((cancel?.isCancelled ?? false) || _closed) {
      throw const StemsDownloadCancelled();
    }
  }

  Future<void> run(File partial, void Function(double)? onProgress) async {
    final step = cache.chunkBytes;
    // The size is usually in the URL (`clen`); the first range confirms it
    // either way, and tells a server that ignores ranges apart.
    final first = await _firstRange(partial, step, onProgress);
    if (first == null) return; // streamed whole (the server ignored the range)
    final (head, total) = first;
    final count = (total + step - 1) ~/ step;
    final parts = List<Uint8List?>.filled(count, null)..[0] = head;
    var received = head.length;
    onProgress?.call((received / total).clamp(0.0, 1.0));
    var nextIndex = 1;

    Future<void> worker() async {
      var client = _open();
      try {
        while (true) {
          _checkCancelled();
          final i = nextIndex++;
          if (i >= count) return;
          final start = i * step;
          final end = (start + step < total ? start + step : total) - 1;
          for (var attempt = 1; ; attempt++) {
            try {
              parts[i] = await _range(client, start, end);
              break;
            } on _Refused {
              rethrow;
            } on StemsDownloadCancelled {
              rethrow;
            } catch (_) {
              // Throttled, cut off or short: a fresh connection, ask again.
              _drop(client);
              client = _open();
              if (attempt >= cache.chunkAttempts) rethrow;
            }
          }
          received += parts[i]!.length;
          onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      } finally {
        _drop(client);
      }
    }

    final workers = cache.parallel < count - 1 ? cache.parallel : count - 1;
    await Future.wait(
      [for (var w = 0; w < workers; w++) worker()],
      eagerError: true,
    );
    _checkCancelled();
    final sink = partial.openWrite();
    try {
      for (final p in parts) {
        sink.add(p!);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  /// The first [step] bytes and the stream's total size, or null after
  /// streaming the whole file because the server answered 200 to a range.
  Future<(Uint8List, int)?> _firstRange(
    File partial,
    int step,
    void Function(double)? onProgress,
  ) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _firstRangeOnce(partial, step, onProgress);
      } on _Refused {
        rethrow;
      } on StemsDownloadCancelled {
        rethrow;
      } catch (_) {
        if (attempt >= cache.chunkAttempts) rethrow;
      }
    }
  }

  Future<(Uint8List, int)?> _firstRangeOnce(
    File partial,
    int step,
    void Function(double)? onProgress,
  ) async {
    final client = _open();
    try {
      final clen = int.tryParse(uri.queryParameters['clen'] ?? '');
      final end = (clen != null && clen < step ? clen : step) - 1;
      final request = await client.getUrl(uri).timeout(cache.chunkTimeout);
      headers.forEach(request.headers.set);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-$end');
      final response = await request.close().timeout(cache.chunkTimeout);
      if (response.statusCode == HttpStatus.ok) {
        await _streamWhole(response, partial, onProgress);
        return null;
      }
      if (response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>().catchError((_) {});
        throw _Refused('HTTP ${response.statusCode}', uri: uri);
      }
      final total =
          _totalFromContentRange(response.headers.value('content-range')) ??
          clen;
      if (total == null || total <= 0) {
        throw _Refused('no stream length', uri: uri);
      }
      final bytes = await _collect(response).timeout(cache.chunkTimeout);
      if (bytes.length != end + 1 && bytes.length != total) {
        throw HttpException('short range', uri: uri);
      }
      return (bytes, total);
    } finally {
      _drop(client);
    }
  }

  Future<Uint8List> _range(HttpClient client, int start, int end) async {
    _checkCancelled();
    final request = await client.getUrl(uri).timeout(cache.chunkTimeout);
    headers.forEach(request.headers.set);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
    final response = await request.close().timeout(cache.chunkTimeout);
    if (response.statusCode != HttpStatus.partialContent) {
      await response.drain<void>().catchError((_) {});
      // A refusal (an expired or proof-gated URL) won't change on asking again.
      throw _Refused('HTTP ${response.statusCode}', uri: uri);
    }
    final bytes = await _collect(response).timeout(cache.chunkTimeout);
    if (bytes.length != end - start + 1) {
      throw HttpException('short range', uri: uri);
    }
    return bytes;
  }

  Future<void> _streamWhole(
    HttpClientResponse response,
    File partial,
    void Function(double)? onProgress,
  ) async {
    final sink = partial.openWrite();
    try {
      final total = response.contentLength;
      var received = 0;
      await for (final chunk in response) {
        _checkCancelled();
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
      }
      await sink.flush();
      if (total > 0 && received != total) {
        throw HttpException('short read ($received of $total)', uri: uri);
      }
    } finally {
      await sink.close();
    }
  }

  static Future<Uint8List> _collect(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// `bytes 0-262143/3526797` → 3526797.
  static int? _totalFromContentRange(String? value) {
    if (value == null) return null;
    final slash = value.lastIndexOf('/');
    return slash < 0 ? null : int.tryParse(value.substring(slash + 1).trim());
  }
}

/// The server said no (an expired or proof-gated URL): asking again is futile.
class _Refused extends HttpException {
  const _Refused(super.message, {super.uri});
}
