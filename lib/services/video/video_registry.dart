/// Which tracks in the queue have a picture.
///
/// # Why a registry rather than a field on the track
///
/// The queue is a list of `SongModel`, which is `on_audio_query`'s shape — a
/// row from the device's media store. It has no room for "and here is the DASH
/// manifest to play it from", and the fields it does have are already carrying
/// more than their names suggest (a streamed track's URL rides in `_data`, its
/// artwork URL in `album`). Adding a third such convention would make the model
/// unreadable and would still not survive the round trip through the media
/// store.
///
/// So videos are recorded beside the queue instead, keyed by the song id the
/// queue already uses. A song not in this map is audio, which is the answer for
/// almost everything the app plays.
///
/// # Manifests are files, and files expire
///
/// A DASH target is a *document*, not a URL: it has to be written somewhere the
/// player can open it. The URLs inside it are single-use and time-limited, so a
/// manifest is worth exactly one viewing. They are written to one directory that
/// is swept at startup, rather than deleted on the way out of a screen — the
/// queue can outlive any screen, and a manifest deleted while its track is still
/// three places down the queue is a track that will not play.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../ytmusic/yt_models.dart';

/// Everything needed to play one track as video.
@immutable
class VideoSource {
  /// The id this track is known by in the queue.
  final int songId;

  /// The YouTube id, for re-resolving when the target below goes stale.
  final String videoId;

  /// What the player opens: a `.mpd` path for DASH, a URL for HLS.
  final String location;

  final YtStreamFormat format;
  final Map<String, String> headers;

  /// Unix seconds after which the CDN stops honouring the URLs in [location].
  final int? expiresAt;

  const VideoSource({
    required this.songId,
    required this.videoId,
    required this.location,
    required this.format,
    required this.headers,
    this.expiresAt,
  });

  /// Whether this can still be handed to a player.
  ///
  /// Mirrors [StreamTarget.isFresh], including its refusal to guess: a target
  /// with no stated deadline is stale immediately, because assuming a lifetime
  /// is how a queue serves a URL the CDN has already stopped honouring.
  bool get isFresh {
    final deadline = expiresAt;
    if (deadline == null) return false;
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 < deadline - 60;
  }

  /// The source the player should load for this track.
  ///
  /// A DASH manifest reaches the player as a file URI so ExoPlayer infers the
  /// format from the `.mpd` extension. The headers still matter and still ride
  /// along: the `BaseURL`s inside the manifest point at googlevideo, which
  /// checks every segment request against the client that resolved it.
  AudioSource toAudioSource({Object? tag}) => switch (format) {
        YtStreamFormat.dash =>
          AudioSource.uri(Uri.file(location), headers: headers, tag: tag),
        _ => AudioSource.uri(Uri.parse(location), headers: headers, tag: tag),
      };
}

/// The videos currently in, or recently in, the queue.
class VideoRegistry {
  VideoRegistry._();

  static final VideoRegistry instance = VideoRegistry._();

  final Map<int, VideoSource> _sources = {};

  /// Where DASH manifests are written. One directory so it can be swept whole.
  static const _manifestDirName = 'hype_video';

  bool isVideo(int songId) => _sources.containsKey(songId);

  VideoSource? sourceFor(int songId) => _sources[songId];

  /// Whether any track in the queue is a video.
  ///
  /// Lets the player decide whether to ask for a surface at all, rather than
  /// attaching one speculatively for a queue of songs.
  bool get isEmpty => _sources.isEmpty;

  void register(VideoSource source) => _sources[source.songId] = source;

  void forget(int songId) => _sources.remove(songId);

  /// Drops everything. Called when a queue that isn't YouTube's takes over.
  void clear() => _sources.clear();

  @visibleForTesting
  void resetForTest() => _sources.clear();

  /// Records [target] for [songId], writing the manifest out when there is one.
  ///
  /// Returns the registered source, or null if the manifest could not be
  /// written — a video that cannot be staged is one the caller should fall back
  /// to audio for rather than queue.
  Future<VideoSource?> adopt({
    required int songId,
    required String videoId,
    required StreamTarget target,
  }) async {
    String location = target.url;
    if (target.format == YtStreamFormat.dash) {
      final file = await _writeManifest(videoId, target.url);
      if (file == null) return null;
      location = file.path;
    }
    final source = VideoSource(
      songId: songId,
      videoId: videoId,
      location: location,
      format: target.format,
      headers: target.headers,
      expiresAt: target.expiresAt,
    );
    register(source);
    return source;
  }

  /// Writes a generated DASH manifest where the player can open it.
  ///
  /// One fixed name per video, overwritten each time: the URLs inside expire, so
  /// two manifests for the same video are never both valid and keeping the older
  /// one only accumulates a file that no longer plays.
  Future<File?> _writeManifest(String videoId, String manifest) async {
    try {
      final directory = Directory(
        '${(await getTemporaryDirectory()).path}/$_manifestDirName',
      );
      if (!directory.existsSync()) await directory.create(recursive: true);
      final file = File('${directory.path}/$videoId.mpd');
      await file.writeAsString(manifest);
      return file;
    } catch (e) {
      debugPrint('Video manifest write failed: $e');
      return null;
    }
  }

  /// Deletes manifests left behind by earlier runs.
  ///
  /// Every one of them is stale by definition — the URLs inside outlive the app
  /// by hours at most, and a manifest from a previous launch has no queue entry
  /// pointing at it. Swept at startup rather than at teardown because a process
  /// that is killed never reaches its teardown.
  Future<void> sweepManifests() async {
    try {
      final directory = Directory(
        '${(await getTemporaryDirectory()).path}/$_manifestDirName',
      );
      if (!directory.existsSync()) return;
      await for (final entry in directory.list()) {
        if (entry is File && entry.path.endsWith('.mpd')) {
          await entry.delete();
        }
      }
    } catch (e) {
      // Stale manifests cost disk, not correctness. Never worth failing a launch.
      debugPrint('Video manifest sweep failed: $e');
    }
  }
}
