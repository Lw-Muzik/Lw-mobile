// ignore_for_file: library_private_types_in_public_api, depend_on_referenced_packages, invalid_use_of_protected_member

import 'package:eq_app/Global/index.dart';
import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/player/PlayerBody.dart';
import 'package:eq_app/player/widgets/Controls.dart';
import 'package:eq_app/player/widgets/Header.dart';
import 'package:eq_app/player/widgets/MusicInfo.dart';
import 'package:eq_app/player/widgets/TrackInfo.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:eq_app/controllers/AppController.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Helpers/AudioVisualizer.dart';
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
      duration: const Duration(milliseconds: 800),
    )..forward();
    // scale animation
    _animation =
        Tween<double>(begin: 0.98, end: 1).animate(_animationController!);
    _animationController?.addStatusListener((status) {});
  }

  @override
  void dispose() {
    super.dispose();
    // if (context.read<AppController>().pageController.hasListeners) {
    //   context.read<AppController>().pageController.
    // }
  }

  Stream<PositionData> get _positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
          context.watch<AppController>().audioPlayer.positionStream,
          context.watch<AppController>().audioPlayer.bufferedPositionStream,
          context.watch<AppController>().audioPlayer.durationStream,
          (position, bufferedPosition, duration) => PositionData(
              position, bufferedPosition, duration ?? Duration.zero));
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: kAppBar,
      body: Consumer<AppController>(
        builder: (context, controller, child) {
          if (controller.songId >= controller.songs.length) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text("Playlist ended"),
            ));
          }
          if (controller.visuals) {
            Visualizers.enableVisual(true);
            // Visualizers.scaleVisualizer(!controller.visuals);
          }
          return StreamBuilder<bool>(
              stream: controller.audioPlayer.playingStream,
              builder: (context, snapshot) {
                bool? result = snapshot.data;
                if (result != null && result) {
                  _animationController?.forward();
                  // log("playing");
                } else {
                  // log("paused");
                  _animationController?.reverse();
                }

                return PlayerBody(
                  controller: controller,
                  child: Stack(
                    children: [
                      if (controller.playerVisual &&
                          controller.audioPlayer.playing)
                        playerVisual(controller),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          SizedBox(height: MediaQuery.of(context).padding.top),
                          const Header(),
                          SizedBox(
                            height: MediaQuery.of(context).size.height - 280,
                            child: Stack(
                              children: <Widget>[
                                SizedBox(
                                  width: MediaQuery.of(context).size.height,
                                  child: PageView.builder(
                                    controller: context
                                        .read<AppController>()
                                        .pageController,
                                    // padEnds: false,
                                    itemCount: controller.songs.length,
                                    onPageChanged: (page) {
                                      if (context
                                          .read<AppController>()
                                          .pageController
                                          .hasClients) {
                                        if (page == controller.songId) {
                                          int x = page + 1;
                                          controller.songId = x;
                                          controller.audioPlayer
                                              .setUrl(controller.songs[x].data);
                                          controller.audioPlayer.play();
                                        } else if (page > controller.songId) {
                                          controller.next();
                                        } else if (page < controller.songId) {
                                          controller.prev();
                                        }
                                        // log("Page $page");
                                      }
                                    },
                                    itemBuilder:
                                        (BuildContext context, int index) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: <Widget>[
                                          // Header2
                                          InkWell(
                                            onTap: () {
                                              Routes.pop(context);
                                              // Routes.routeTo(
                                              //     controller.nowWidget,
                                              //     context);
                                            },
                                            onLongPress: () {
                                              showModalBottomSheet(
                                                  context: context,
                                                  builder: (context) {
                                                    return BottomSheet(
                                                        onClosing: () {},
                                                        builder: (context) {
                                                          return TrackInfo(
                                                            controller:
                                                                controller,
                                                          );
                                                        });
                                                  });
                                            },
                                            child: playerCard(_animation!,
                                                context, controller),
                                          ),
                                          SizedBox(
                                              height: MediaQuery.of(context)
                                                  .padding
                                                  .top),
                                          MusicInfo(controller: controller),
                                        ],
                                      );
                                    },
                                  ),
                                )
                              ],
                            ),
                          ),

                          StreamBuilder<PositionData>(
                            stream: _positionDataStream,
                            builder: (context, snapshot) {
                              final positionData = snapshot.data;
                              return SeekBar(
                                duration:
                                    positionData?.duration ?? Duration.zero,
                                position:
                                    positionData?.position ?? Duration.zero,
                                bufferedPosition:
                                    positionData?.bufferedPosition ??
                                        Duration.zero,
                                onChangeEnd: context
                                    .watch<AppController>()
                                    .audioPlayer
                                    .seek,
                              );
                            },
                          ),
                          // slider
                          Controls(controller: controller),
                        ],
                      ),
                    ],
                  ),
                );
              });
        },
      ),
    );
  }
}
