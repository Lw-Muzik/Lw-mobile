/// The things a streamed track needs to remember about itself.
///
/// # Why these ride in the map
///
/// A queue entry is a `SongModel` — `on_audio_query`'s shape, a row from the
/// device's media store. It has no field for "and this is YouTube video
/// `dQw4w9WgXcQ`, whose URL stops working at 14:32". But it is a thin wrapper
/// over a plain map that it copies verbatim and ignores keys it does not know,
/// so extra keys survive both construction and a round trip through JSON.
///
/// That matters for saving a session. A googlevideo URL is single-use and
/// expires in about six hours; a queue restored the next morning holds a list of
/// dead links and nothing to rebuild them from. Keeping the video id turns a
/// dead entry into one request.
///
/// The `hype_` prefix keeps these clear of every key the media store might
/// itself define.
library;

import 'package:on_audio_query/on_audio_query.dart';

/// The extra keys this app writes into a track's map.
class TrackKeys {
  const TrackKeys._();

  /// The YouTube id, so an expired URL can be resolved again.
  static const videoId = 'hype_video_id';

  /// Unix seconds after which the stored URL stops working.
  static const expiresAt = 'hype_expires_at';

  /// Whether this entry was queued to be *watched* rather than heard.
  static const isVideo = 'hype_is_video';
}

extension TrackExtras on SongModel {
  /// The YouTube id, or null for anything this app did not stream from YouTube.
  String? get ytVideoId => getMap[TrackKeys.videoId] as String?;

  /// Whether this entry is a music video rather than an audio stream.
  bool get isYtVideo => getMap[TrackKeys.isVideo] == true;

  /// Whether the stored URL can still be handed to a player.
  ///
  /// Mirrors `StreamTarget.isFresh`, including its refusal to guess: an entry
  /// with no recorded deadline is stale, because assuming a lifetime is how a
  /// restored queue serves a URL the CDN stopped honouring hours ago. A track
  /// that never came from YouTube has no deadline to miss and is always fresh.
  bool get hasFreshTarget {
    if (ytVideoId == null) return true;
    final deadline = (getMap[TrackKeys.expiresAt] as num?)?.toInt();
    if (deadline == null) return false;
    // A minute of headroom, so a URL cannot expire mid-buffer.
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 < deadline - 60;
  }

  /// Whether this entry must be resolved again before it can be handed to a
  /// player.
  ///
  /// [staged] is whether a video's DASH manifest is currently registered. It is
  /// a parameter rather than a lookup so this stays a pure function of the
  /// track and one fact about it.
  ///
  /// A video needs both halves to be true. Its deadline says only that the URLs
  /// *inside* the manifest are still honoured; it says nothing about whether the
  /// manifest itself is still on disk. Manifests are swept at every launch — one
  /// left by a previous run has no queue entry pointing at it — so a video the
  /// process died two minutes after resolving comes back with a live deadline
  /// and no file behind it. Trusting the deadline alone hands the player a path
  /// to something that is not there.
  bool needsRefresh({required bool staged}) {
    if (ytVideoId == null) return false;
    if (!hasFreshTarget) return true;
    return isYtVideo && !staged;
  }

  /// A copy of this track pointing at [url], valid until [expiresAt].
  ///
  /// Used when a stale entry has been resolved again: everything the user sees —
  /// title, artist, artwork, the id the queue knows it by — is preserved, and
  /// only the link changes.
  SongModel withTarget(String url, int? expiresAt) => SongModel({
        ...getMap,
        '_data': url,
        TrackKeys.expiresAt: expiresAt,
      });
}
