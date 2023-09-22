import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/widgets/ArtworkWidget.dart';
import 'package:eq_app/widgets/Globals.dart';
import 'package:flutter/material.dart';

import '../controllers/AppController.dart';
import '../player/PlayerUI.dart';

class BottomPlayer extends StatefulWidget {
  final AppController controller;
  const BottomPlayer({super.key, required this.controller});

  @override
  State<BottomPlayer> createState() => _BottomPlayerState();
}

class _BottomPlayerState extends State<BottomPlayer>
    with TickerProviderStateMixin {
  // @override
  // void initState() {
  //   super.initState();
  //   _animationController = AnimationController(
  //     vsync: this,
  //     value: 0,
  //     duration: const Duration(milliseconds: 95000),
  //   )..repeat();
  //   _animation =
  //       Tween<double>(begin: 0, end: 358).animate(_animationController!);

  //   WidgetsBinding.instance.addPostFrameCallback((_) {
  //     var player =
  //         Provider.of<AppController>(context, listen: false).audioPlayer;

  //     if (player.playing) {
  //       _animationController!.repeat();
  //     } else {
  //       _animationController!.stop();
  //     }
  //   });
  // }

  // @override
  // void dispose() {
  //   super.dispose();
  //   // _animationController!.dispose();
  // }

  @override
  Widget build(BuildContext context) {
    return Routes.animateTo(
      closedWidget: ArtworkWidget(
        useSaved: true,
        path: widget.controller.songs[widget.controller.songId].data,
        songId: widget.controller.songs[widget.controller.songId].id,
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.width / 5.7,
        margin: const EdgeInsets.only(left: 10, bottom: 30, right: 10),
        borderRadius: BorderRadius.circular(50),
        child: bottomPlayer(widget.controller, context),
      ),
      openWidget: const Player(),
    );
  }
}
