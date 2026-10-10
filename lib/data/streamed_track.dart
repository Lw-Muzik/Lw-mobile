/// A streamed (YouTube) song the user has played.
///
/// Play events are keyed by song id and kept for streamed tracks as well, but
/// the songs table only knows local files — so without this record a streamed
/// play is a number with no title, and the mixes could never be built from it.
/// Kept in `library_meta` under `yt:<videoId>`: an addition that needs no
/// schema migration.
library;

import 'dart:convert';

import 'package:on_audio_query/on_audio_query.dart';

import '../models/track_extras.dart';

class StreamedTrack {
  const StreamedTrack({
    required this.videoId,
    required this.songId,
    required this.title,
    this.artist,
    this.thumbnail,
    this.durationMs = 0,
    required this.lastPlayedSec,
  });

  final String videoId;

  /// The id the player and the play-event log know this track by.
  final int songId;
  final String title;
  final String? artist;
  final String? thumbnail;
  final int durationMs;
  final int lastPlayedSec;

  static const keyPrefix = 'yt:';
  String get key => '$keyPrefix$videoId';

  /// The record for a playing queue entry, or null when it isn't streamed.
  static StreamedTrack? fromSong(SongModel song, int nowSec) {
    final videoId = song.ytVideoId;
    if (videoId == null || videoId.isEmpty) return null;
    final artist = song.artist;
    final art = song.album;
    return StreamedTrack(
      videoId: videoId,
      songId: song.id,
      title: song.title,
      // The fallback the YouTube path fills in when it has no artist.
      artist: artist == null || artist == 'YouTube Music' ? null : artist,
      // Streamed entries carry their artwork URL in `album`.
      thumbnail: art != null && art.startsWith('http') ? art : null,
      durationMs: song.duration ?? 0,
      lastPlayedSec: nowSec,
    );
  }

  String encode() => jsonEncode({
    'v': videoId,
    'id': songId,
    't': title,
    if (artist != null) 'a': artist,
    if (thumbnail != null) 'th': thumbnail,
    'd': durationMs,
    'at': lastPlayedSec,
  });

  static StreamedTrack? decode(String? raw) {
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return StreamedTrack(
        videoId: m['v'] as String,
        songId: (m['id'] as num).toInt(),
        title: m['t'] as String,
        artist: m['a'] as String?,
        thumbnail: m['th'] as String?,
        durationMs: (m['d'] as num?)?.toInt() ?? 0,
        lastPlayedSec: (m['at'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}
