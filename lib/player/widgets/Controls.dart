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
                IconButton(
                  highlightColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  onPressed: () {
                    setState(() {
                      isLoop = !isLoop;
                    });
                    widget.controller.audioPlayer
                        .setLoopMode(isLoop ? LoopMode.one : LoopMode.off);
                  },
                  icon: Icon(
                    isLoop ? Icons.repeat_one : Icons.repeat,
                    color: Colors.white.withOpacity(isLoop ? 0.9 : 0.4),
                  ),
                ),
                IconButton(
                  iconSize: 32,
                  onPressed: () => widget.controller.prev(),
                  icon: const Icon(Icons.skip_previous, color: Colors.white),
                ),
                ControlButtons(widget.controller.audioPlayer),
                IconButton(
                  iconSize: 32,
                  onPressed: () => widget.controller.next(),
                  icon: const Icon(Icons.skip_next, color: Colors.white),
                ),
                IconButton(
                  highlightColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  onPressed: () {
                    setState(() {
                      isShuffle = !isShuffle;
                    });
                    widget.controller.audioPlayer
                        .setShuffleModeEnabled(isShuffle);
                  },
                  icon: Icon(
                    isShuffle ? Icons.shuffle_on_rounded : Icons.shuffle,
                    color: Colors.white.withOpacity(isShuffle ? 0.9 : 0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
