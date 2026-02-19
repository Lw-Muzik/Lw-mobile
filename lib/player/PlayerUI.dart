// ignore_for_file: library_private_types_in_public_api
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/Global/index.dart';
import '/Routes/routes.dart';
import '/player/PlayerBody.dart';
import '/player/widgets/Controls.dart';
import '/player/widgets/Header.dart';
import '/player/widgets/MusicInfo.dart';
import '/controllers/AppController.dart';
import '/Helpers/AudioVisualizer.dart';
import '/widgets/common.dart';
import 'swipe_animation.dart';

// Main Player Widget
class Player extends StatefulWidget {
  const Player({super.key});

  @override
  _PlayerState createState() => _PlayerState();
}

class _PlayerState extends State<Player> with TickerProviderStateMixin {
  AnimationController? _animationController;
  Animation<double>? _animation;
  PageController? _pageController;
  bool isChangingTrack = false;
  // final GlobalKey<State<AnimatedPlayerCard>> _playerCardKey = GlobalKey();
  @override
  void initState() {
    super.initState();
    checkPermissionForAudioVisualization();
    _initializeAnimationController();
  }

  void _initializeAnimationController() {
    _animationController = AnimationController(
      vsync: this,
      value: 0,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _animation = Tween<double>(
      begin: 0.98,
      end: 1,
    ).animate(_animationController!);
  }

  void checkPermissionForAudioVisualization() {
    Permission.microphone.request().then((value) {
      if (value.isGranted) {
        Visualizers.enableVisual(true);
      } else {
        Visualizers.enableVisual(false);
      }
    });
  }

  Stream<PositionData> get _positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
        context.watch<AppController>().handler.player.positionStream,
        context.watch<AppController>().handler.player.bufferedPositionStream,
        context.watch<AppController>().handler.player.durationStream,
        (position, bufferedPosition, duration) =>
            PositionData(position, bufferedPosition, duration ?? Duration.zero),
      );

  @override
  void dispose() {
    _pageController?.dispose();
    _animationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<AppController>(
        builder: (context, controller, child) {
          return StreamBuilder(
            stream: controller.handler.player.playingStream,
            builder: (context, snapshot) {
              bool? isPlaying = snapshot.data;

              if (isPlaying ?? false) {
                _animationController?.forward();
              } else {
                _animationController?.reverse();
              }

              return PlayerBody(
                controller: controller,
                child: Stack(
                  children: [
                    if (controller.playerVisual && isPlaying != null)
                      playerVisual(controller),
                    SizedBox(
                      height: MediaQuery.of(context).size.height,
                      width: MediaQuery.of(context).size.width,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          SizedBox(height: MediaQuery.of(context).padding.top),
                          const Header(),
                          SizedBox(
                            height: MediaQuery.of(context).size.height - 290,
                            child: AnimatedPlayerCard(
                              //  key: _playerCardKey,
                              itemCount: controller.songs.length,
                              currentSongId: controller.songId,
                              onPageChanged: (page) {
                                if (page > controller.songId) {
                                  controller.next();
                                } else {
                                  controller.prev();
                                }
                              },
                              itemBuilder:
                                  (context, index, {bool isActive = false}) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: <Widget>[
                                        InkWell(
                                          onTap: () => Routes.pop(context),
                                          onLongPress: () => showTrackInfo(
                                            context,
                                            controller,
                                          ),
                                          child: AnimatedSwitcher(
                                            duration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            child: playerCard(
                                              _animation!,
                                              context,
                                              controller,
                                            ),
                                          ),
                                        ),
                                        // Only show MusicInfo for the active card
                                        if (isActive)
                                          AnimatedOpacity(
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            opacity: isActive ? 1.0 : 0.0,
                                            child: MusicInfo(
                                              controller: controller,
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                            ),
                          ),
                          // Seek bar
                          FittedBox(
                            child: SizedBox(
                              width: MediaQuery.of(context).size.width,
                              child: StreamBuilder<PositionData>(
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
                                    onChangeEnd: controller.handler.player.seek,
                                  );
                                },
                              ),
                            ),
                          ),
                          const Controls(
                            // playerCard: _playerCardKey.currentState!.widget,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
