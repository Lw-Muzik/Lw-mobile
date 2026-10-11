/// Every YouTube download by video id: the ones running and the ones done.
///
/// # Why one place
///
/// A download used to be fire-and-forget from whichever screen started it, so
/// nothing could tell that a track was already downloading or already saved —
/// and a second tap saved a second copy. Everything that offers a download
/// asks here first: the player's song actions show "Downloading 40%" or
/// "Downloaded", and asking for a download that is already running joins it.
///
/// What was saved is remembered in the library database (`ytdl:<videoId>` →
/// path) so it survives a restart. A file the user has since deleted is not a
/// download any more, so the path is checked every time it is asked for.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/library_repository.dart';
import 'yt_download.dart';
import 'yt_models.dart';
import 'yt_song_tags.dart';

typedef YtDownloadFn =
    Future<YtDownloadResult> Function(
      YtTrack track, {
      void Function(double fraction)? onProgress,
    });

class YtDownloads {
  YtDownloads._();

  static final instance = YtDownloads._();

  /// The download itself; replaceable in tests.
  @visibleForTesting
  YtDownloadFn downloader = YtDownloader.download;

  LibraryRepository? _repo;

  /// Wired at startup, like `ArtworkService` — the record of what was saved
  /// lives beside the library it was saved into.
  void attachRepository(LibraryRepository repo) => _repo = repo;

  final _running = <String, _Running>{};

  /// Moves on whenever a download starts or ends.
  final ValueNotifier<int> changes = ValueNotifier(0);

  static const _key = 'ytdl:';

  /// Whether [videoId] is downloading right now.
  bool isRunning(String videoId) => _running.containsKey(videoId);

  /// How far [videoId]'s download is (0–1, null while its length is still
  /// unknown), or null when it isn't downloading.
  ValueListenable<double?>? progressOf(String videoId) =>
      _running[videoId]?.progress;

  /// Downloads [track], or joins its download if one is already running.
  Future<YtDownloadResult> download(
    YtTrack track, {
    void Function(double fraction)? onProgress,
  }) {
    final running = _running[track.videoId];
    if (running != null) {
      if (onProgress != null) running.listeners.add(onProgress);
      return running.result;
    }
    final run = _Running();
    if (onProgress != null) run.listeners.add(onProgress);
    _running[track.videoId] = run;
    changes.value++;
    run.result = downloader(
      track,
      onProgress: (fraction) {
        run.progress.value = fraction;
        for (final listener in run.listeners) {
          listener(fraction);
        }
      },
    ).then((result) async {
      if (result is YtDownloadSaved) await remember(track.videoId, result.path);
      return result;
    }).whenComplete(() {
      _running.remove(track.videoId);
      changes.value++;
    });
    return run.result;
  }

  /// Records that [videoId] lives at [path] — a download, or an old download
  /// the repair identified.
  Future<void> remember(String videoId, String path) async {
    await _repo?.metaSet('$_key$videoId', path);
    changes.value++;
  }

  /// Where this track already is on the phone, or null.
  ///
  /// A download of it, first; failing that a library song with the same title
  /// that credits the same artist — a track downloaded before downloads were
  /// recorded, or one the user had all along. Either way, downloading it again
  /// would only make a copy.
  Future<String?> localCopy(
    String videoId, {
    required String title,
    String? artist,
  }) async {
    final repo = _repo;
    if (repo == null) return null;
    final saved = await repo.metaGet('$_key$videoId');
    if (saved != null && saved.isNotEmpty && await _exists(saved)) {
      return saved;
    }
    if (artist == null || artist.isEmpty || artist == 'YouTube Music') {
      return null;
    }
    for (final song in await repo.songsTitled(title)) {
      if (song.data.startsWith('http')) continue;
      if (creditsInclude(song.artist, artist) && await _exists(song.data)) {
        return song.data;
      }
    }
    return null;
  }

  static Future<bool> _exists(String path) async {
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }
}

class _Running {
  final progress = ValueNotifier<double?>(null);
  final listeners = <void Function(double)>[];
  late final Future<YtDownloadResult> result;
}
