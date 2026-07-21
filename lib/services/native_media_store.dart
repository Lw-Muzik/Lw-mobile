import 'dart:io';

import 'package:flutter/services.dart';

/// Thin bridge to the native Android MediaStore importer (see
/// `android/app/src/main/kotlin/x/a/zix/MediaImporter.java`).
///
/// Why this exists rather than a plain file write: the app targets SDK 36, so
/// it is fully under scoped storage. `WRITE_EXTERNAL_STORAGE` is ignored from
/// API 30 and `requestLegacyExternalStorage` only ever applied through API 29,
/// which leaves inserting into `MediaStore.Audio.Media` as the only sanctioned
/// way to put a file in the shared music tree. The insert doubles as the
/// registration — the row *is* what `OnAudioQuery` reads, so a received track
/// shows up in the phone's own library (and can be streamed back to the
/// desktop) with no separate scan.
///
/// Like [NativeMdns], the channel is attached to whichever `FlutterEngine`
/// hosts the sharing server — on Android the flutter_foreground_task background
/// engine (see `HypeMediaStoreLifecycleListener`), since that's where the
/// upload endpoint runs.
///
/// No-op on non-Android platforms.
class NativeMediaStore {
  const NativeMediaStore._();

  static const MethodChannel _channel = MethodChannel('x.a.zix/media_store');

  /// Whether the MediaStore path is available (Android only).
  static bool get supported => Platform.isAndroid;

  /// Publish [sourcePath] into the shared music library under [displayName].
  ///
  /// Returns `{'id': String, 'path': String?}` — the MediaStore id and the
  /// on-disk path the row resolves to (what `OnAudioQuery` reports as a song's
  /// `data`, so `/stream` can serve the track straight back) — or null when the
  /// insert failed.
  static Future<Map<String, dynamic>?> importAudio({
    required String sourcePath,
    required String displayName,
    required String mimeType,
  }) async {
    if (!supported) return null;
    final result = await _channel.invokeMethod<Map>('importAudio', {
      'sourcePath': sourcePath,
      'displayName': displayName,
      'mimeType': mimeType,
    });
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }
}
