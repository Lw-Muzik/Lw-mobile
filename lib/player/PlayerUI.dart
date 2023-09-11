// ignore_for_file: library_private_types_in_public_api, depend_on_referenced_packages

import 'dart:developer';

import 'package:eq_app/Global/index.dart';
import 'package:eq_app/player/PlayerBody.dart';
import 'package:eq_app/player/widgets/Controls.dart';
import 'package:eq_app/player/widgets/Header.dart';
import 'package:eq_app/player/widgets/MusicInfo.dart';
import 'package:rxdart/rxdart.dart';
import 'package:eq_app/controllers/AppController.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
      appBar: kAppBar,
      body: Consumer<AppController>(
        builder: (context, controller, child) {
          if (controller.songId == controller.songs.length) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text("Playlist ended"),
            ));
          }
          return StreamBuilder<bool>(
              stream: controller.audioPlayer.playingStream,
              builder: (context, snapshot) {
                bool? result = snapshot.data;
                if (result != null && result) {
                  _animationController?.forward();
                  log("playing");
                } else {
                  log("paused");
                  _animationController?.reverse();
                }

                return PlayerBody(
                  controller: controller,
                  child: Column(
                    children: <Widget>[
                      SizedBox(
                        height: MediaQuery.of(context).size.height - 240,
                        child: Stack(
                          children: <Widget>[
                            Column(
                              children: <Widget>[
                                SizedBox(
                                    height: MediaQuery.of(context).padding.top),
                                // Header
                                const Header(),
                                playerCard(_animation!, context, controller),
                                SizedBox(
                                    height: MediaQuery.of(context).padding.top),
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
                            onChangeEnd:
                                context.watch<AppController>().audioPlayer.seek,
                          );
                        },
                      ),
                      // slider
                      Controls(controller: context.watch<AppController>()),
                      if (controller.playerVisual &&
                          controller.audioPlayer.playing)
                        playerVisual(controller),
                    ],
                  ),
                );
              });
        },
      ),
    );
  }
}
