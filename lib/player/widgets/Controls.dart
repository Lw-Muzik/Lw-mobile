// ignore_for_file: must_be_immutable

import 'package:eq_app/controllers/AppController.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../Helpers/AudioHandler.dart';
import '../../Helpers/Eq.dart';
import 'package:flutter/material.dart';

class Controls extends StatefulWidget {
  const Controls({super.key});

  @override
  State<Controls> createState() => _ControlsState();
}

class _ControlsState extends State<Controls> {
  bool isLoop = false;

  bool isShuffle = false;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      child: SizedBox(
        height: 150,
        width: MediaQuery.of(context).size.width,
        child: Consumer<AppController>(builder: (context, controller, c) {
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    StreamBuilder<LoopMode>(
                      stream: controller.handler.player.loopModeStream,
                      builder: (context, snapshot) {
                        final loopMode = snapshot.data ?? LoopMode.off;
                        const icons = [
                          Icon(Icons.repeat, color: Colors.grey),
                          Icon(Icons.repeat, color: Colors.orange),
                          Icon(Icons.repeat_one, color: Colors.orange),
                        ];
                        const cycleModes = [
                          LoopMode.off,
                          LoopMode.all,
                          LoopMode.one,
                        ];
                        final index = cycleModes.indexOf(loopMode);
                        return IconButton(
                          icon: icons[index],
                          onPressed: () {
                            controller.handler.player.setLoopMode(cycleModes[
                                (cycleModes.indexOf(loopMode) + 1) %
                                    cycleModes.length]);
                          },
                        );
                      },
                    ),
                    IconButton(
                      iconSize: 32,
                      onPressed: () => controller.prev(),
                      icon: const Icon(Icons.skip_previous, color: Colors.white),
                    ),
                    const ControlButtons(),
                    IconButton(
                      iconSize: 32,
                      onPressed: () => controller.next(),
                      icon: const Icon(Icons.skip_next, color: Colors.white),
                    ),
                    StreamBuilder<bool>(
                      stream: context
                          .read<AudioHandler>()
                          .player
                          .shuffleModeEnabledStream,
                      builder: (context, snapshot) {
                        final shuffleModeEnabled = snapshot.data ?? false;
                        return IconButton(
                          icon: shuffleModeEnabled
                              ? const Icon(Icons.shuffle, color: Colors.orange)
                              : const Icon(Icons.shuffle, color: Colors.grey),
                          onPressed: () async {
                            setState(() {});
                            final enable = !shuffleModeEnabled;
                            setState(() {});
                            controller.isShuffled = enable;
                            if (enable) {
                              controller.shuffleSongs();
                            } else {}
                            context
                                .read<AudioHandler>()
                                .player
                                .setShuffleModeEnabled(enable);
                          },
                        );
                      },
                    ),
                    // IconButton(
                    //   highlightColor: Colors.transparent,
                    //   splashColor: Colors.transparent,
                    //   onPressed: () {
                    //     setState(() {
                    //       isShuffle = !isShuffle;
                    //     });
                    //     controller.audioPlayer
                    //         .setShuffleModeEnabled(isShuffle);
                    //   },
                    //   icon: Icon(
                    //     isShuffle ? Icons.shuffle_on_rounded : Icons.shuffle,
                    //     color: Colors.white.withOpacity(isShuffle ? 0.9 : 0.4),
                    //   ),
                    // ),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
