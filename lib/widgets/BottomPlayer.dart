import 'dart:ui';

import 'package:eq_app/widgets/Globals.dart';
import 'package:flutter/material.dart';

import '../controllers/AppController.dart';

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
    return bottomPlayer(widget.controller, context);
  }
}
