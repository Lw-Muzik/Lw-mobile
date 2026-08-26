/// One track in a mix, before it is playable.
///
/// # Why a reference and not a `SongModel`
///
/// A local file is playable the moment it is read out of the database. A drive
/// file needs a link minted for it — a request each, on Dropbox. A YouTube
/// track needs resolving, which is another request and produces a URL that
/// expires in hours.
///
/// Building six mixes of twenty-five tracks would therefore mean up to a hundred
/// and fifty requests, on opening the home page, for cards the user may never
/// tap — and most of those URLs would be dead by the time they did. So a mix
/// holds references, and resolution happens when one is played.
library;

import 'package:on_audio_query/on_audio_query.dart';

import '../../models/cloud_file.dart';
import '../ytmusic/yt_models.dart';
import 'daily_mixes.dart';

class MixTrackRef {
  const MixTrackRef._({
    required this.source,
    required this.title,
    this.artist,
    this.song,
    this.file,
    this.track,
  });

  factory MixTrackRef.local(SongModel song) => MixTrackRef._(
        source: MixSource.local,
        title: song.title,
        artist: song.artist,
        song: song,
      );

  factory MixTrackRef.cloud(CloudFile file) => MixTrackRef._(
        source: MixSource.cloud,
        title: file.trackTitle ?? file.name,
        artist: file.trackArtist,
        file: file,
      );

  factory MixTrackRef.youtube(YtTrack track) => MixTrackRef._(
        source: MixSource.youtube,
        title: track.title,
        artist: track.artist,
        track: track,
      );

  final MixSource source;
  final String title;
  final String? artist;

  /// Set for a local track, which needs nothing further.
  final SongModel? song;

  /// Set for a drive track, which needs a link minted.
  final CloudFile? file;

  /// Set for a YouTube track, which needs resolving.
  final YtTrack? track;

  /// Whether this can be handed to the player as it stands.
  bool get isReady => song != null;
}
