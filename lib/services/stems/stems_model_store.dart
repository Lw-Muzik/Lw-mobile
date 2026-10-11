/// Downloads, verifies and locates the stems separation model.
///
/// # Nothing unverified gets its real name
///
/// Each file streams to `<name>.part` while its SHA-256 is computed on the
/// same bytes, so a 20 MB file is never held in memory and never read twice.
/// Only a file whose size *and* fingerprint both match the embedded manifest
/// is renamed to the name the native loader opens. A `ready.json` marker is
/// written after all four pass; [StemsModelStore.isReady] wants the marker and
/// every file at its exact size.
///
/// # Resume
///
/// A download interrupted by a cancel, a dead connection or a killed process
/// leaves at most one `.part` file behind, which the next attempt overwrites.
/// Files that already verified are kept and re-checked rather than fetched
/// again; a file whose fingerprint no longer matches is deleted and fetched.
///
/// # Fallback
///
/// Each file lists its URLs in order — our host, then Hugging Face. A host
/// that answers with the wrong length (a web server's catch-all HTML page is
/// the usual culprit) is abandoned at the headers, before a byte is saved.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'stems_manifest.dart';

/// What the store is doing, for the UI's "Checking files…" vs a progress bar.
enum StemsDownloadPhase { checking, downloading }

@immutable
class StemsDownloadProgress {
  final int receivedBytes;
  final int totalBytes;

  const StemsDownloadProgress(this.receivedBytes, this.totalBytes);

  double get fraction =>
      totalBytes <= 0 ? 0 : (receivedBytes / totalBytes).clamp(0.0, 1.0);
}

/// The download was cancelled by the user. Not a failure.
class StemsDownloadCancelled implements Exception {
  const StemsDownloadCancelled();

  @override
  String toString() => 'StemsDownloadCancelled';
}

/// The download could not be completed from any URL.
class StemsDownloadException implements Exception {
  /// A sentence fit to show the user.
  final String message;

  /// What actually went wrong, for logs.
  final Object? cause;

  const StemsDownloadException(this.message, [this.cause]);

  @override
  String toString() =>
      'StemsDownloadException: $message${cause == null ? '' : ' ($cause)'}';
}

/// Cancels a download in flight, including one still waiting on headers.
class StemsCancelToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  /// Completes (never with an error) when [cancel] is called.
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

class StemsModelStore {
  StemsModelStore({
    this.manifest = StemsModelManifest.spleeter4StemsFp16,
    http.Client Function()? clientFactory,
    Future<Directory> Function()? baseDirectory,
    this.connectTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 30),
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _baseDirectory = baseDirectory ?? getApplicationSupportDirectory;

  final StemsModelManifest manifest;
  final http.Client Function() _clientFactory;
  final Future<Directory> Function() _baseDirectory;

  /// How long to wait for a server to answer with headers.
  final Duration connectTimeout;

  /// How long a transfer may go without a byte before it counts as dead.
  final Duration idleTimeout;

  static const markerName = 'ready.json';
  static const partSuffix = '.part';

  /// `<application support>/stems/<id>-v<version>`.
  Future<Directory> directory() async {
    final base = await _baseDirectory();
    return Directory('${base.path}/stems/${manifest.directoryName}');
  }

  /// Whether a verified copy of every file is on disk. Cheap — sizes only; the
  /// fingerprints were checked when the files were written.
  Future<bool> isReady() async {
    try {
      final dir = await directory();
      final marker = File('${dir.path}/$markerName');
      if (!await marker.exists()) return false;
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is! Map ||
          decoded['id'] != manifest.id ||
          decoded['version'] != manifest.version) {
        return false;
      }
      for (final f in manifest.files) {
        final file = File('${dir.path}/${f.name}');
        if (!await file.exists() || await file.length() != f.size) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fetches whatever is missing and verifies all of it.
  ///
  /// Throws [StemsDownloadCancelled] when [cancel] fires and
  /// [StemsDownloadException] when a file can't be had from any of its URLs.
  Future<void> download({
    void Function(StemsDownloadProgress progress)? onProgress,
    void Function(StemsDownloadPhase phase)? onPhase,
    StemsCancelToken? cancel,
  }) async {
    final token = cancel ?? StemsCancelToken();
    final total = manifest.totalBytes;
    if (await isReady()) {
      onProgress?.call(StemsDownloadProgress(total, total));
      return;
    }

    final dir = await directory();
    try {
      await dir.create(recursive: true);
      // A marker that outlived one of its files says "ready" about a model
      // that isn't. It comes back only once everything verifies again.
      final marker = File('${dir.path}/$markerName');
      if (await marker.exists()) await marker.delete();
    } on FileSystemException catch (e) {
      throw StemsDownloadException(_messageFor(e), e);
    }

    onPhase?.call(StemsDownloadPhase.checking);
    var done = 0;
    final pending = <StemsModelFile>[];
    for (final f in manifest.files) {
      _throwIfCancelled(token);
      final file = File('${dir.path}/${f.name}');
      if (await _isVerified(file, f)) {
        done += f.size;
        continue;
      }
      await _deleteQuietly(file);
      pending.add(f);
    }
    _throwIfCancelled(token);
    onProgress?.call(StemsDownloadProgress(done, total));

    if (pending.isNotEmpty) {
      onPhase?.call(StemsDownloadPhase.downloading);
      final client = _clientFactory();
      try {
        for (final f in pending) {
          final base = done;
          await _downloadFile(
            client,
            dir,
            f,
            token,
            (received) =>
                onProgress?.call(StemsDownloadProgress(base + received, total)),
          );
          done += f.size;
        }
      } finally {
        client.close();
      }
    }

    _throwIfCancelled(token);
    try {
      await File('${dir.path}/$markerName').writeAsString(
        jsonEncode({
          'id': manifest.id,
          'version': manifest.version,
          'files': {for (final f in manifest.files) f.name: f.sha256},
          'verifiedAt': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
    } on FileSystemException catch (e) {
      throw StemsDownloadException(_messageFor(e), e);
    }
    onProgress?.call(StemsDownloadProgress(total, total));
  }

  /// Removes every file of this model version, marker first.
  Future<void> delete() async {
    final dir = await directory();
    final marker = File('${dir.path}/$markerName');
    await _deleteQuietly(marker);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  // ---------------------------------------------------------------------------

  Future<void> _downloadFile(
    http.Client client,
    Directory dir,
    StemsModelFile f,
    StemsCancelToken token,
    void Function(int received) onBytes,
  ) async {
    final target = File('${dir.path}/${f.name}');
    final part = File('${target.path}$partSuffix');
    Object? lastError;
    for (final url in f.urls) {
      _throwIfCancelled(token);
      try {
        await _fetchVerified(client, Uri.parse(url), f, part, token, onBytes);
        // The only way a file gets the name the native loader opens.
        await part.rename(target.path);
        return;
      } on StemsDownloadCancelled {
        await _deleteQuietly(part);
        rethrow;
      } catch (e) {
        lastError = e;
        await _deleteQuietly(part);
        // Bytes from an attempt that didn't verify were never really received.
        onBytes(0);
        debugPrint('Stems model: ${f.name} from $url failed: $e');
      }
    }
    throw StemsDownloadException(_messageFor(lastError), lastError);
  }

  /// Streams [url] into [part], hashing as it goes, and throws unless the
  /// result is exactly the file the manifest describes.
  Future<void> _fetchVerified(
    http.Client client,
    Uri url,
    StemsModelFile f,
    File part,
    StemsCancelToken token,
    void Function(int received) onBytes,
  ) async {
    final abort = Completer<void>();
    void triggerAbort() {
      if (!abort.isCompleted) abort.complete();
    }

    unawaited(token.whenCancelled.then((_) => triggerAbort()));
    final request = http.AbortableRequest(
      'GET',
      url,
      abortTrigger: abort.future,
    );

    final http.StreamedResponse response;
    try {
      response = await client.send(request).timeout(connectTimeout);
    } on TimeoutException {
      triggerAbort();
      rethrow;
    } on http.RequestAbortedException {
      if (token.isCancelled) throw const StemsDownloadCancelled();
      rethrow;
    }

    if (token.isCancelled) {
      await _discard(response);
      throw const StemsDownloadCancelled();
    }
    if (response.statusCode != 200) {
      await _discard(response);
      throw _HttpStatusError(response.statusCode, url);
    }
    final length = response.contentLength;
    if (length != null && length >= 0 && length != f.size) {
      await _discard(response);
      throw _MismatchError('size', '${f.size}', '$length');
    }

    final raf = await part.open(mode: FileMode.write);
    final digest = _DigestCapture();
    final hasher = sha256.startChunkedConversion(digest);
    final finished = Completer<void>();
    Future<void>? pendingWrite;
    Timer? idle;
    var received = 0;
    var completed = false;

    void fail(Object error) {
      if (!finished.isCompleted) finished.completeError(error);
    }

    void armIdle() {
      idle?.cancel();
      idle = Timer(
        idleTimeout,
        () => fail(TimeoutException('No data for $idleTimeout', idleTimeout)),
      );
    }

    late final StreamSubscription<List<int>> sub;
    sub = response.stream.listen(
      (chunk) {
        received += chunk.length;
        if (received > f.size) {
          fail(_MismatchError('size', '${f.size}', 'more than that'));
          return;
        }
        hasher.add(chunk);
        // One write at a time, and no more bytes until it lands: the network
        // can outrun the disk, and an unpaused stream would queue the
        // difference in memory.
        sub.pause();
        pendingWrite = raf.writeFrom(chunk).then((_) {
          // A transfer that already failed stays failed: no progress, no new
          // idle timer, no more bytes.
          if (finished.isCompleted) return;
          onBytes(received);
          armIdle();
          sub.resume();
        }, onError: fail);
      },
      onError: fail,
      onDone: () {
        if (!finished.isCompleted) finished.complete();
      },
      cancelOnError: true,
    );

    try {
      armIdle();
      unawaited(
        token.whenCancelled.then((_) => fail(const StemsDownloadCancelled())),
      );
      await finished.future;
      await pendingWrite;
      await raf.flush();
      completed = true;
    } finally {
      idle?.cancel();
      await sub.cancel();
      if (!completed) {
        try {
          await pendingWrite;
        } catch (_) {
          // The failure that ended the transfer is the one worth reporting.
        }
      }
      await raf.close();
    }

    hasher.close();
    if (received != f.size) {
      throw _MismatchError('size', '${f.size}', '$received');
    }
    final actual = digest.value?.toString();
    if (actual != f.sha256) {
      throw _MismatchError('fingerprint', f.sha256, '$actual');
    }
  }

  Future<bool> _isVerified(File file, StemsModelFile f) async {
    try {
      if (!await file.exists() || await file.length() != f.size) return false;
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString() == f.sha256;
    } catch (_) {
      return false;
    }
  }

  static void _throwIfCancelled(StemsCancelToken token) {
    if (token.isCancelled) throw const StemsDownloadCancelled();
  }

  static Future<void> _discard(http.StreamedResponse response) async {
    try {
      await response.stream.listen((_) {}).cancel();
    } catch (_) {
      // Nothing to salvage from a response being thrown away.
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A leftover file is overwritten by the next attempt anyway.
    }
  }

  static String _messageFor(Object? error) => switch (error) {
    SocketException() ||
    HandshakeException() ||
    TimeoutException() ||
    http.ClientException() => 'Check your connection and try again.',
    FileSystemException() =>
      "Couldn't save the files. Check your free space and try again.",
    _MismatchError() => "The download didn't check out. Try again.",
    _HttpStatusError() => "The download server didn't answer. Try again later.",
    _ => "The download didn't finish. Try again.",
  };
}

class _HttpStatusError implements Exception {
  final int status;
  final Uri url;

  const _HttpStatusError(this.status, this.url);

  @override
  String toString() => 'HTTP $status from $url';
}

class _MismatchError implements Exception {
  final String what;
  final String expected;
  final String actual;

  const _MismatchError(this.what, this.expected, this.actual);

  @override
  String toString() => '$what mismatch: expected $expected, got $actual';
}

class _DigestCapture implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
