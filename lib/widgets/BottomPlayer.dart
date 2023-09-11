import 'dart:typed_data';
import 'dart:ui';

import 'package:eq_app/widgets/Globals.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

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
    return StreamBuilder<Uint8List?>(
        stream: Stream.fromFuture(
          widget.controller.audioQuery.queryArtwork(
              widget.controller.songs[widget.controller.songId].id,
              ArtworkType.AUDIO,
              quality: 100,
              format: ArtworkFormat.PNG,
              size: 2),
        ),
        builder: (context, snapshot) {
          return Container(
            // height: 70,
            width: MediaQuery.of(context).size.width,
            margin: const EdgeInsets.only(left: 10, bottom: 30, right: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(50),
              // color: Colors.white70,
              image: DecorationImage(
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                      snapshot.hasData ? Colors.black26 : Colors.black,
                      BlendMode.darken),
                  image: snapshot.hasData
                      ? MemoryImage(snapshot.data!)
                      : const AssetImage("assets/audio.jpeg") as ImageProvider),
            ),
            child: bottomPlayer(widget.controller, context),
          );
        });
  }
}
