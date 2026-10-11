/// Naming a track from its sound, and writing what was found into it.
///
/// Shared by the library's song options and the player's song actions, which
/// used to carry the same steps twice. Both report outcomes as words for the
/// user rather than exceptions: every failure here is something they can act
/// on ("play it first") or simply be told.
library;

import 'dart:io';

import 'package:on_audio_query/on_audio_query.dart';

import '../controllers/app_controller.dart';
import '../Helpers/Channel.dart';
import '../models/recognition_result.dart';

/// What identifying a track came to: a result, or why there is none.
typedef Identification = ({RecognitionResult? result, String? error});

/// Identifies [song] by audio fingerprint.
///
/// A drive track is fingerprinted from its cached copy — the stream itself
/// can't be — so one that has never played has nothing to listen to yet.
Future<Identification> identifyTrack(SongModel song) async {
  final controller = AppController.instance;
  String? fingerprintPath;
  if (song.data.startsWith('http')) {
    final fileId = song.id.toString();
    if (!controller.cloudCache.isCached(fileId)) {
      return (result: null, error: 'Not cached yet — play it through first');
    }
    fingerprintPath = controller.cloudCache.cacheFile(fileId).path;
  }
  try {
    final result = await controller.fingerprintService.identifySong(
      song,
      fingerprintPath: fingerprintPath,
    );
    if (result == null || !result.hasUsefulData) {
      return (result: null, error: 'Could not identify this track');
    }
    return (result: result, error: null);
  } catch (_) {
    return (result: null, error: 'Identification failed');
  }
}

/// Writes [result] into [song]: its tags (local files only — a stream can't
/// be written to) and its cover, then shows them everywhere at once.
///
/// Null on success, otherwise what went wrong.
Future<String?> applyIdentification(
  SongModel song,
  RecognitionResult result,
) async {
  final controller = AppController.instance;
  final tags = result.toTagMap();
  if (tags.isEmpty) return 'No tags to write';

  String? artworkPath;
  try {
    if (result.musicBrainzReleaseId != null) {
      artworkPath = await controller.fingerprintService.fetchCoverArt(
        result.musicBrainzReleaseId!,
      );
    }
    if (!song.data.startsWith('http')) {
      final ok = await Channel.writeTags(
        song.data,
        tags,
        artworkPath: artworkPath,
      );
      if (!ok) return 'Failed to write tags';
      await Channel.scanMediaFile(song.data);
    }
    await controller.updateSongMetadata(
      song,
      result,
      newArtworkPath: artworkPath,
    );
    return null;
  } catch (_) {
    return 'Failed to write tags';
  } finally {
    if (artworkPath != null) {
      try {
        File(artworkPath).deleteSync();
      } catch (_) {}
    }
  }
}
