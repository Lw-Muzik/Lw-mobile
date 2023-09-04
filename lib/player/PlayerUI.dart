// ignore_for_file: library_private_types_in_public_api, depend_on_referenced_packages

import 'dart:developer';

import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/player/PlayerBody.dart';
import 'package:eq_app/player/widgets/Controls.dart';
import 'package:eq_app/player/widgets/Header.dart';
import 'package:eq_app/player/widgets/MusicInfo.dart';
import 'package:eq_app/player/widgets/PlayerSettings.dart';
import 'package:rxdart/rxdart.dart';
import 'package:eq_app/controllers/AppController.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../pages/VisualUI.dart';
import '../widgets/common.dart';

class Player extends StatefulWidget {
  const Player({super.key});

  @override
  _PlayerState createState() => _PlayerState();
}

class _PlayerState extends State<Player> with TickerProviderStateMixin {
  AnimationController? _animationController;
  Animation<double>? _animation;
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      value: 0,
      duration: const Duration(milliseconds: 1000),
    )..forward();
    // scale animation
    _animation =
        Tween<double>(begin: 0.98, end: 1).animate(_animationController!);
    _animationController?.addStatusListener((status) {});
  }

  @override
  void dispose() {
    // if (mounted) {
    //   _animationController?.dispose();
    // }

    super.dispose();
  }

  Stream<PositionData> get _positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
          context.read<AppController>().audioPlayer.positionStream,
          context.read<AppController>().audioPlayer.bufferedPositionStream,
          context.read<AppController>().audioPlayer.durationStream,
          (position, bufferedPosition, duration) => PositionData(
              position, bufferedPosition, duration ?? Duration.zero));
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: kAppBar,
      body: Consumer<AppController>(
        builder: (context, controller, child) {
          controller.audioPlayer.playingStream.listen((event) {
            if (event) {
              _animationController?.forward();
              log("playing");
            } else {
              log("paused");
              _animationController?.reverse();
            }
          });

          return PlayerBody(
            controller: controller,
            child: Column(
              children: <Widget>[
                SizedBox(
                  height: MediaQuery.of(context).size.height - 210,
                  child: Stack(
                    children: <Widget>[
                      Column(
                        children: <Widget>[
                          SizedBox(height: MediaQuery.of(context).padding.top),
                          // Header
                          const Header(),
                          AnimatedBuilder(
                              animation: _animation!,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: _animation!.value,
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                        right: 28.0,
                                        top: 10,
                                        bottom: 10,
                                        left: 28),
                                    child: SizedBox(
                                      height: MediaQuery.of(context).size.width,
                                      width: MediaQuery.of(context).size.width,
                                      child: QueryArtworkWidget(
                                        quality: 100,
                                        artworkBorder:
                                            BorderRadius.circular(15),
                                        size: 1000,
                                        id: controller
                                            .songs[controller.songId].id,
                                        format: ArtworkFormat.PNG,
                                        type: ArtworkType.AUDIO,
                                        nullArtworkWidget: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: Image.asset(
                                            "assets/audio.jpeg",
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                          Padding(
                            padding: const EdgeInsets.only(
                                right: 20.0, top: 10, bottom: 10, left: 20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  color: Colors.white,
                                  onPressed: () =>
                                      Routes.routeTo(const VisualUI(), context),
                                  icon: const Icon(Icons.graphic_eq_rounded),
                                ),
                                IconButton(
                                  onPressed: () => showModalBottomSheet(
                                    context: context,
                                    builder: (context) {
                                      return BottomSheet(
                                        onClosing: () {},
                                        builder: (context) {
                                          return PlayerSettings(
                                            controller: controller,
                                          );
                                        },
                                      );
                                    },
                                  ),
                                  color: Colors.white,
                                  icon: const Icon(Icons.more_vert_rounded),
                                )
                              ],
                            ),
                          ),
                          MusicInfo(controller: controller),
                        ],
                      )
                    ],
                  ),
                ),

                StreamBuilder<PositionData>(
                  stream: _positionDataStream,
                  builder: (context, snapshot) {
                    final positionData = snapshot.data;
                    return SeekBar(
                      duration: positionData?.duration ?? Duration.zero,
                      position: positionData?.position ?? Duration.zero,
                      bufferedPosition:
                          positionData?.bufferedPosition ?? Duration.zero,
                      onChangeEnd: controller.audioPlayer.seek,
                    );
                  },
                ),
                // slider
                Controls(controller: controller),
              ],
            ),
          );
        },
      ),
    );
  }
}
