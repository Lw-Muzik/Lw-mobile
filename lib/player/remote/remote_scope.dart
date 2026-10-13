/// Shared plumbing for the remote-mode player UI.
library;

import 'package:flutter/material.dart';

import 'package:eq_app/services/connect/connect_protocol.dart';
import 'package:eq_app/services/connect/hype_connect.dart';
import 'package:eq_app/services/connect/remote/connect_remote_session.dart';
import 'package:eq_app/themes/ember.dart';

/// The Connect glyph used wherever the UI says "on another device".
const IconData kConnectGlyph = Icons.cast_connected_rounded;

/// Rebuilds with the remote device's player, or null outside remote mode.
class RemoteBuilder extends StatelessWidget {
  const RemoteBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, RemoteNowPlaying? remote) builder;

  @override
  Widget build(BuildContext context) {
    final connect = HypeConnect.instanceOrNull;
    if (connect == null) return builder(context, null);
    return ListenableBuilder(
      listenable: connect,
      builder: (context, _) {
        final session = connect.session;
        if (session == null) return builder(context, null);
        return ListenableBuilder(
          listenable: session,
          builder: (context, _) => builder(context, session.nowPlaying()),
        );
      },
    );
  }
}

/// Artwork of a remote track: its public thumbnail, else a quiet placeholder
/// (a `local` file's art lives on the other device).
class RemoteArt extends StatelessWidget {
  const RemoteArt({
    super.key,
    required this.track,
    required this.size,
    this.radius = 8,
  });

  final TrackRef? track;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = switch (track) {
      YtTrackRef(:final artUrl) => artUrl,
      OtherTrackRef(:final artUrl) => artUrl,
      _ => null,
    };
    final placeholder = Container(
      width: size,
      height: size,
      color: Ember.surfaceHigh,
      child: Icon(
        Icons.music_note_rounded,
        color: Ember.textTertiary,
        size: size * 0.4,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url == null
          ? placeholder
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * 2).round(),
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

String remoteTitleOf(TrackRef? track) => switch (track) {
      YtTrackRef(:final title) => title,
      LocalTrackRef(:final title) => title,
      OtherTrackRef(:final title) => title,
      null => 'Nothing playing',
    };

String? remoteArtistOf(TrackRef? track) => switch (track) {
      YtTrackRef(:final artist) => artist,
      LocalTrackRef(:final artist) => artist,
      OtherTrackRef(:final artist) => artist,
      null => null,
    };

IconData iconForDevice(DeviceKind kind) => switch (kind) {
      DeviceKind.web => Icons.language_rounded,
      DeviceKind.desktop => Icons.desktop_mac_rounded,
      DeviceKind.mobile => Icons.smartphone_rounded,
    };

String formatMs(int ms) {
  final total = ms ~/ 1000;
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
