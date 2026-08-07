/// Building a DASH manifest out of YouTube's adaptive formats.
///
/// # Why this has to exist
///
/// YouTube serves music videos as *adaptive* streams — video and audio as
/// separate files. A player has to combine them, and `video_player` cannot: it
/// takes one URL. Measured live across six real music videos, the only client
/// that resolves them at all (IOS) returns:
///
/// * no muxed format (`formats` is empty), so there is no single-file shortcut;
/// * no `hlsManifestUrl` for most of them, so YouTube's own combined manifest
///   isn't on offer either.
///
/// What it *does* return is every field a DASH manifest needs — `initRange`,
/// `indexRange`, `contentLength`, codecs, bitrate, dimensions. So the manifest
/// is written here, from those, and handed to the player as a local file whose
/// `BaseURL`s point at YouTube's CDN. ExoPlayer plays that natively, quality
/// switching included.
///
/// # The platform limit, stated plainly
///
/// DASH is an Android capability. iOS's AVPlayer supports HLS and not DASH, so
/// on iOS this path is unavailable and the caller says so rather than handing
/// AVPlayer something it will fail to open. Videos for which YouTube *does*
/// offer HLS play on both.
library;

import 'yt_json.dart';

/// One rendition, reduced to what a manifest needs.
class DashStream {
  final int itag;
  final String url;
  final String codecs;
  final int bitrate;
  final String initRange;
  final String indexRange;
  final int? width;
  final int? height;
  final int? fps;
  final int? audioSampleRate;

  const DashStream({
    required this.itag,
    required this.url,
    required this.codecs,
    required this.bitrate,
    required this.initRange,
    required this.indexRange,
    this.width,
    this.height,
    this.fps,
    this.audioSampleRate,
  });
}

/// Reads one adaptive format, or null if it can't take part in a manifest.
///
/// A format missing its byte ranges is unusable: `SegmentBase` addressing is
/// what lets a player seek inside a single remote file, and guessing the ranges
/// would produce a manifest that opens and then stalls.
DashStream? readStream(Object? format) {
  final url = ptrString(format, 'url');
  if (url == null) return null;
  final itag = ptr(format, 'itag');
  if (itag is! int) return null;

  final initStart = ptrString(format, 'initRange/start');
  final initEnd = ptrString(format, 'initRange/end');
  final indexStart = ptrString(format, 'indexRange/start');
  final indexEnd = ptrString(format, 'indexRange/end');
  if (initStart == null ||
      initEnd == null ||
      indexStart == null ||
      indexEnd == null) {
    return null;
  }

  final mime = ptrString(format, 'mimeType') ?? '';
  final codecs = RegExp(r'codecs="([^"]+)"').firstMatch(mime)?.group(1);
  if (codecs == null) return null;

  final bitrate = ptr(format, 'bitrate');
  return DashStream(
    itag: itag,
    url: url,
    codecs: codecs,
    bitrate: bitrate is num ? bitrate.toInt() : 0,
    initRange: '$initStart-$initEnd',
    indexRange: '$indexStart-$indexEnd',
    width: (ptr(format, 'width') as num?)?.toInt(),
    height: (ptr(format, 'height') as num?)?.toInt(),
    fps: (ptr(format, 'fps') as num?)?.toInt(),
    audioSampleRate: int.tryParse(ptrString(format, 'audioSampleRate') ?? ''),
  );
}

/// A DASH manifest for [video] renditions plus one [audio] rendition.
///
/// Only H.264-in-MP4 video is passed in by [buildDashManifest]'s caller: an
/// adaptation set must hold one container and codec family, and AVC is the
/// rendition every Android device can decode in hardware.
String buildDashManifest({
  required List<DashStream> video,
  required DashStream audio,
  required Duration duration,
}) {
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" '
      'profiles="urn:mpeg:dash:profile:isoff-on-demand:2011" '
      'type="static" mediaPresentationDuration="${_iso(duration)}" '
      'minBufferTime="PT1.5S">',
    )
    ..writeln('  <Period>');

  if (video.isNotEmpty) {
    buffer.writeln(
      '    <AdaptationSet mimeType="video/mp4" contentType="video" '
      'subsegmentAlignment="true">',
    );
    // Highest quality last: players read the list in order and this is the
    // conventional ascending arrangement.
    final sorted = [...video]..sort((a, b) => a.bitrate.compareTo(b.bitrate));
    for (final stream in sorted) {
      buffer
        ..writeln(
          '      <Representation id="${stream.itag}" '
          'codecs="${_escape(stream.codecs)}" bandwidth="${stream.bitrate}" '
          'width="${stream.width ?? 0}" height="${stream.height ?? 0}" '
          'frameRate="${stream.fps ?? 30}" startWithSAP="1">',
        )
        ..writeln('        <BaseURL>${_escape(stream.url)}</BaseURL>')
        ..writeln('        <SegmentBase indexRange="${stream.indexRange}">')
        ..writeln('          <Initialization range="${stream.initRange}"/>')
        ..writeln('        </SegmentBase>')
        ..writeln('      </Representation>');
    }
    buffer.writeln('    </AdaptationSet>');
  }

  buffer
    ..writeln(
      '    <AdaptationSet mimeType="audio/mp4" contentType="audio" '
      'subsegmentAlignment="true">',
    )
    ..writeln(
      '      <Representation id="${audio.itag}" '
      'codecs="${_escape(audio.codecs)}" bandwidth="${audio.bitrate}" '
      'audioSamplingRate="${audio.audioSampleRate ?? 44100}" '
      'startWithSAP="1">',
    )
    ..writeln(
      '        <AudioChannelConfiguration '
      'schemeIdUri="urn:mpeg:dash:23003:3:audio_channel_configuration:2011" '
      'value="2"/>',
    )
    ..writeln('        <BaseURL>${_escape(audio.url)}</BaseURL>')
    ..writeln('        <SegmentBase indexRange="${audio.indexRange}">')
    ..writeln('          <Initialization range="${audio.initRange}"/>')
    ..writeln('        </SegmentBase>')
    ..writeln('      </Representation>')
    ..writeln('    </AdaptationSet>')
    ..writeln('  </Period>')
    ..writeln('</MPD>');

  return buffer.toString();
}

/// A duration as DASH states it: `PT223.958S`.
String _iso(Duration duration) {
  final seconds = duration.inMilliseconds / 1000;
  return 'PT${seconds.toStringAsFixed(3)}S';
}

/// XML-escapes a value.
///
/// Load-bearing for the URLs: googlevideo targets are a long string of query
/// parameters separated by `&`, and an unescaped one makes the manifest
/// malformed XML that the player rejects outright.
String _escape(String raw) => raw
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
