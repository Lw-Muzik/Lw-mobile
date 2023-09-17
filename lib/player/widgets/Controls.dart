// ignore_for_file: must_be_immutable

import 'package:eq_app/controllers/AppController.dart';
import 'package:just_audio/just_audio.dart';

import '../../Helpers/Eq.dart';
import 'package:flutter/material.dart';

class Controls extends StatefulWidget {
  final AppController controller;
  const Controls({super.key, required this.controller});

  @override
  State<Controls> createState() => _ControlsState();
}

class _ControlsState extends State<Controls> {
  bool isLoop = false;

  bool isShuffle = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                // IconButton(
                //   highlightColor: Colors.transparent,
                //   splashColor: Colors.transparent,
                //   onPressed: () {
                //     setState(() {
                //       isLoop = !isLoop;
                //     });
                //     widget.controller.audioPlayer
                //         .setLoopMode(isLoop ? LoopMode.one : LoopMode.off);
                //   },
                //   icon: Icon(
                //     isLoop ? Icons.repeat_one : Icons.repeat,
                //     color: Colors.white.withOpacity(isLoop ? 0.9 : 0.4),
                //   ),
                // ),
                StreamBuilder<LoopMode>(
                  stream: widget.controller.audioHandler.loopModeStream,
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
                        widget.controller.audioHandler.setLoopMode(cycleModes[
                            (cycleModes.indexOf(loopMode) + 1) %
                                cycleModes.length]);
                      },
                    );
                  },
                ),
                IconButton(
                  iconSize: 32,
                  onPressed: () => widget.controller.prev(),
                  icon: const Icon(Icons.skip_previous, color: Colors.white),
                ),
                ControlButtons(widget.controller.audioHandler),
                IconButton(
                  iconSize: 32,
                  onPressed: () => widget.controller.next(),
                  icon: const Icon(Icons.skip_next, color: Colors.white),
                ),
                StreamBuilder<bool>(
                  stream:
                      widget.controller.audioHandler.shuffleModeEnabledStream,
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
                        widget.controller.isShuffled = enable;
                        if (enable) {
                          widget.controller.shuffleSongs();
                        } else {}
                        widget.controller.audioHandler
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
                //     widget.controller.audioPlayer
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
      ),
    );
  }
}
