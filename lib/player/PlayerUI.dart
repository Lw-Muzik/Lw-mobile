// ignore_for_file: library_private_types_in_public_api, depend_on_referenced_packages, invalid_use_of_protected_member
import 'package:permission_handler/permission_handler.dart';

import '../Helpers/Channel.dart';
import '/Global/index.dart';
import '/Routes/routes.dart';
import '/player/PlayerBody.dart';
import '/player/widgets/Controls.dart';
import '/player/widgets/Header.dart';
import '/player/widgets/MusicInfo.dart';
import 'package:rxdart/rxdart.dart';
import '/controllers/AppController.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/Helpers/AudioVisualizer.dart';
import '/widgets/common.dart';

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
    checkPermissionForAudioVisualization();
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

  void checkPermissionForAudioVisualization() {
    Permission.microphone.request().then((value) {
      if (value.isGranted) {
        Visualizers.enableVisual(true);
        // log("P")
      } else {
        // context.read<AppController>().visuals = false;
        Visualizers.enableVisual(false);
      }
    });
  }

  Stream<PositionData> get _positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
          context.watch<AppController>().handler.player.positionStream,
          context.watch<AppController>().handler.player.bufferedPositionStream,
          context.watch<AppController>().handler.player.durationStream,
          (position, bufferedPosition, duration) => PositionData(
              position, bufferedPosition, duration ?? Duration.zero));

  /// A stream reporting the combined state of the current media item and its
  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: kAppBar,
      body: Consumer<AppController>(
        builder: (context, controller, child) {
          final PageController pageController =
              PageController(initialPage: controller.songId);
          if (controller.songId >= (controller.songs.length - 1)) {
            Channel.showNativeMessage("Songs playlist ended.");
          }
          if (controller.visuals) {
            Visualizers.enableVisual(true);
            // Visualizers.scaleVisualizer(!controller.visuals);
          }
          return StreamBuilder(
              stream: controller.handler.player.playingStream,
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
                      if (controller.playerVisual && result != null)
                        playerVisual(controller),
                      FittedBox(
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height,
                          width: MediaQuery.of(context).size.width,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              SizedBox(
                                  height: MediaQuery.of(context).padding.top),
                              const Header(),
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height - 280,
                                child: Stack(
                                  children: <Widget>[
                                    SizedBox(
                                      // width: MediaQuery.of(context).size.width,
                                      // height: MediaQuery.of(context).size.width,
                                      child: PageView.builder(
                                        controller: pageController,
                                        // padEnds: false,
                                        itemCount: controller.songs.length,
                                        onPageChanged: (page) {
                                          setState(() {});
                                          if (pageController.hasClients) {
                                            if (page == controller.songId) {
                                              int x = page + 1;
                                              setState(() {});
                                              if (x >=
                                                  controller.songs.length) {
                                                x = 0;
                                                setState(() {});
                                              } else {
                                                controller.songId = x;
                                                loadAudioSource(
                                                    controller.handler,
                                                    controller.songs[x]);
                                                setState(() {});
                                              }
                                            } else if (page >
                                                controller.songId) {
                                              controller.next();
                                              setState(() {});
                                            } else if (page <
                                                controller.songId) {
                                              controller.prev();
                                              setState(() {});
                                            }
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
                                                },
                                                onLongPress: () =>
                                                    showTrackInfo(
                                                        context, controller),
                                                child: playerCard(_animation!,
                                                    context, controller),
                                              ),
                                              MusicInfo(controller: controller),
                                            ],
                                          );
                                        },
                                      ),
                                    )
                                  ],
                                ),
                              ),

                              FittedBox(
                                child: SizedBox(
                                  width: MediaQuery.of(context).size.width,
                                  child: StreamBuilder<PositionData>(
                                    stream: _positionDataStream,
                                    builder: (context, snapshot) {
                                      final positionData = snapshot.data;
                                      return SeekBar(
                                        duration: positionData?.duration ??
                                            Duration.zero,
                                        position: positionData?.position ??
                                            Duration.zero,
                                        bufferedPosition:
                                            positionData?.bufferedPosition ??
                                                Duration.zero,
                                        onChangeEnd:
                                            controller.handler.player.seek,
                                      );
                                    },
                                  ),
                                ),
                              ),
                              // slider
                              const Controls(),
                            ],
                          ),
                        ),
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
