/// Which files on this phone came from YouTube, so stems can refuse them.
///
/// YouTube's Developer Policies (III.I.7) forbid separating or isolating the
/// audio of YouTube content, and a download is still YouTube content. Streams
/// are easy to tell apart — they are URLs. Downloads are not:
///
/// * on Android they are published into `Music/HypeMuzik`, the same folder
///   Phone Link uploads (the user's own music) land in;
/// * on iOS they shared `Documents/Music` with the user's own imports until
///   they got a `YouTube` folder of their own.
///
/// A folder can't tell those apart, so every file `YtDownloader` saves is
/// written down here by its exact path, and the stems engine is handed the
/// list as "excluded prefixes" (an exact path is a prefix of itself).
///
/// Downloads made before this ledger existed are found by their container:
/// YouTube serves DASH audio, whose `ftyp` box names `dash` as its major
/// brand. Only the app's own download folders are swept, once per session.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class YtDownloadRegistry extends ChangeNotifier {
  YtDownloadRegistry({
    Future<SharedPreferences> Function()? prefs,
    Future<String?> Function()? documentsPath,
  }) : _prefs = prefs ?? SharedPreferences.getInstance,
       _documentsPath = documentsPath ?? _defaultDocumentsPath;

  static final YtDownloadRegistry instance = YtDownloadRegistry();

  static const prefsKey = 'yt_downloaded_paths_v1';

  /// Far more than anyone downloads; only there so the list can't grow
  /// without bound. The oldest entries go first.
  static const maxEntries = 5000;

  final Future<SharedPreferences> Function() _prefs;
  final Future<String?> Function() _documentsPath;

  Future<int>? _sweep;

  /// Every recorded path, absolute, as it is on this install.
  Future<List<String>> paths() async {
    final prefs = await _prefs();
    final docs = await _documentsPath();
    return [
      for (final entry in prefs.getStringList(prefsKey) ?? const <String>[])
        ?decodePath(entry, docs),
    ];
  }

  Future<void> record(String path) => recordAll([path]);

  /// Adds [paths] that aren't already known. Returns how many were new.
  Future<int> recordAll(Iterable<String> paths) async {
    final prefs = await _prefs();
    final docs = await _documentsPath();
    final entries = [...?prefs.getStringList(prefsKey)];
    final known = entries.toSet();
    var added = 0;
    for (final path in paths) {
      if (path.isEmpty) continue;
      final entry = encodePath(path, docs);
      if (known.add(entry)) {
        entries.add(entry);
        added++;
      }
    }
    if (added == 0) return 0;
    if (entries.length > maxEntries) {
      entries.removeRange(0, entries.length - maxEntries);
    }
    await prefs.setStringList(prefsKey, entries);
    notifyListeners();
    return added;
  }

  /// Finds downloads saved before the ledger existed. Runs once per session:
  /// a folder that couldn't be read this time (Android before the audio
  /// permission is granted) is simply tried again next launch.
  Future<int> sweepLegacyDownloads() => _sweep ??= _sweepDefaultFolders();

  Future<int> _sweepDefaultFolders() async {
    try {
      return await sweep(await _legacyFolders());
    } catch (e) {
      debugPrint('YtDownloadRegistry: legacy sweep failed: $e');
      return 0;
    }
  }

  /// Records every YouTube-DASH `.m4a` directly inside [folders] (not in
  /// sub-folders: a user's own music filed away deeper is none of this
  /// sweep's business). Returns how many were new.
  Future<int> sweep(Iterable<Directory> folders, {int limit = 2000}) async {
    final found = <String>[];
    var seen = 0;
    for (final folder in folders) {
      try {
        if (!await folder.exists()) continue;
        await for (final entity in folder.list(followLinks: false)) {
          if (entity is! File) continue;
          if (!entity.path.toLowerCase().endsWith('.m4a')) continue;
          if (++seen > limit) break;
          if (await isYouTubeDash(entity)) found.add(entity.path);
        }
      } on FileSystemException catch (e) {
        debugPrint('YtDownloadRegistry: cannot list ${folder.path}: $e');
      }
    }
    return found.isEmpty ? 0 : recordAll(found);
  }

  /// Whether [file] is an MP4 whose major brand is `dash` — how YouTube's
  /// audio-only streams (itag 140 and friends) arrive, byte for byte, when
  /// saved without remuxing.
  static Future<bool> isYouTubeDash(File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      final head = await raf.read(12);
      if (head.length < 12) return false;
      return String.fromCharCodes(head, 4, 8) == 'ftyp' &&
          String.fromCharCodes(head, 8, 12) == 'dash';
    } catch (_) {
      return false;
    } finally {
      await raf?.close();
    }
  }

  /// Where this app has ever put YouTube downloads, minus the iOS `YouTube`
  /// folder (excluded wholesale already).
  static Future<List<Directory>> _legacyFolders() async {
    if (Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      return [Directory('${docs.path}/Music')];
    }
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      final root = external == null ? null : sharedStorageRoot(external.path);
      if (root != null) return [Directory('$root/Music/HypeMuzik')];
    }
    return const [];
  }

  /// The shared-storage root (`/storage/emulated/0`) from the app's own
  /// external directory (`/storage/emulated/0/Android/data/<pkg>/files`).
  static String? sharedStorageRoot(String appExternalPath) {
    final i = appExternalPath.indexOf('/Android/');
    return i > 0 ? appExternalPath.substring(0, i) : null;
  }

  /// Paths inside the app's Documents folder are stored relative to it.
  ///
  /// iOS moves an app's container to a new UUID on update, so an absolute
  /// path recorded today would point nowhere after the next release.
  static String encodePath(String path, String? documents) {
    if (documents == null || documents.isEmpty) return path;
    final p = _withoutPrivate(path);
    final d = _withoutPrivate(documents);
    if (p.startsWith('$d/')) return '$_docsScheme${p.substring(d.length + 1)}';
    return path;
  }

  static String? decodePath(String entry, String? documents) {
    if (!entry.startsWith(_docsScheme)) return entry;
    if (documents == null || documents.isEmpty) return null;
    return '$documents/${entry.substring(_docsScheme.length)}';
  }

  static const _docsScheme = 'docs:';

  /// iOS reports the same file as `/var/…` or `/private/var/…` depending on
  /// who resolved the symlink.
  static String _withoutPrivate(String path) => path.startsWith('/private/var/')
      ? path.substring('/private'.length)
      : path;

  static Future<String?> _defaultDocumentsPath() async {
    try {
      return (await getApplicationDocumentsDirectory()).path;
    } catch (_) {
      return null;
    }
  }
}
