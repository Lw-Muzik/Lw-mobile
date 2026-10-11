import 'dart:ui';

import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/widgets/artwork_widget.dart';
import 'package:eq_app/widgets/globals.dart';
import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../player/player_presence.dart';
import '../player/player_ui.dart';

class BottomPlayer extends StatefulWidget {
  final AppController controller;
  const BottomPlayer({super.key, required this.controller});

  @override
  State<BottomPlayer> createState() => _BottomPlayerState();
}

class _BottomPlayerState extends State<BottomPlayer>
    with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    if (!widget.controller.hasNowPlaying) return const SizedBox.shrink();
    final song = widget.controller.songs[widget.controller.songId];
    final closed = ArtworkWidget(
      useSaved: true,
      path: song.data,
      songId: song.id,
      width: MediaQuery.of(context).size.width - 24,
      height: 64,
      borderRadius: BorderRadius.circular(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: bottomPlayer(widget.controller, context),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: PlayerPresence.isOpen
          // This page was opened from the player: going back to it beats
          // opening a second one on top.
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Routes.playerTo(context),
              child: closed,
            )
          : Routes.animateTo(
              closedWidget: closed,
              openWidget: const Player(),
              routeSettings: const RouteSettings(
                name: PlayerPresence.routeName,
              ),
            ),
    );
  }
}
