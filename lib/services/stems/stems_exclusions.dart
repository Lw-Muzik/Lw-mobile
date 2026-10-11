/// The paths the native stems engine must treat as YouTube's.
///
/// The engine separates any local file the player opens. Three kinds of local
/// file are YouTube content, which its Developer Policies forbid separating:
///
/// * DASH manifests of YouTube videos, which the player opens from the temp
///   directory ([VideoRegistry.manifestDirectoryPath]);
/// * iOS downloads, in their own `Documents/Music/YouTube` folder;
/// * every download [YtDownloadRegistry] recorded, by exact path — on Android
///   they sit in `Music/HypeMuzik` beside the user's own Phone Link uploads,
///   so no folder rule can single them out.
///
/// Directory prefixes end in `/`, so `…/YouTube/` can't swallow a sibling
/// called `…/YouTube Mixes/`.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../video/video_registry.dart';
import '../ytmusic/yt_download.dart';
import '../ytmusic/yt_download_registry.dart';

class StemsExclusions {
  const StemsExclusions._();

  static Future<List<String>> collect() async {
    final raw = <String>[];
    try {
      raw.add(asDirectoryPrefix(await VideoRegistry.manifestDirectoryPath()));
    } catch (e) {
      debugPrint('StemsExclusions: no video manifest directory: $e');
    }
    if (Platform.isIOS) {
      try {
        raw.add(
          asDirectoryPrefix(await YtDownloader.iosDownloadDirectoryPath()),
        );
      } catch (e) {
        debugPrint('StemsExclusions: no YouTube download directory: $e');
      }
    }
    try {
      raw.addAll(await YtDownloadRegistry.instance.paths());
    } catch (e) {
      debugPrint('StemsExclusions: download ledger unreadable: $e');
    }
    return expandExcludedPrefixes(raw, isIOS: Platform.isIOS);
  }
}

/// [path] with exactly one trailing `/`, marking it as a directory prefix.
String asDirectoryPrefix(String path) => path.endsWith('/') ? path : '$path/';

/// De-duplicates [raw], keeping order, and on iOS adds each path's twin:
/// the same file is `/var/mobile/…` to one API and `/private/var/mobile/…` to
/// another, and a prefix check doesn't follow symlinks.
List<String> expandExcludedPrefixes(
  Iterable<String> raw, {
  required bool isIOS,
}) {
  final out = <String>{};
  for (final path in raw) {
    if (path.isEmpty) continue;
    out.add(path);
    if (!isIOS) continue;
    if (path.startsWith('/private/var/')) {
      out.add(path.substring('/private'.length));
    } else if (path.startsWith('/var/')) {
      out.add('/private$path');
    }
  }
  return out.toList();
}
