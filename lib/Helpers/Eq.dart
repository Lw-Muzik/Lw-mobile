import 'dart:math';

import 'package:eq_app/Helpers/Channel.dart';
import 'package:eq_app/extensions/index.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../controllers/AppController.dart';

class EqualizerControls extends StatelessWidget {
  const EqualizerControls({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(builder: (context, eq, state) {
      return StreamBuilder<List<int>>(
        stream: Stream.fromFuture(Channel.getBandFreq()),
        builder: (context, snapshot) {
          final bands = snapshot.data;

          return Row(
            children: [
              ...List.generate(
                bands?.length ?? 0,
                (i) => Expanded(
                  child: StreamBuilder<int>(
                      stream: Stream.fromFuture(Channel.getBandLevel(i)),
                      builder: (context, level) {
                        int? l = level.data;

                        if (l != null) {
                          l = level.data;
                        }
                        eq.bandValues[i] = l ?? 0;
                        // });

                        return Column(
                          children: [
                            if (l != null) Text("$l Hz"),
                            SizedBox(
                              width: MediaQuery.of(context).size.width,
                              height: MediaQuery.of(context).size.height / 3.53,
                              child: VerticalSlider(
                                min: -15,
                                max: 15,
                                value: level.data?.toDouble() ?? 0,
                                onChanged: (value) {
                                  eq.bandValues[i] = value.toInt();

                                  Channel.setBandLevel(i, value.toInt());
                                },
                              ),
                            ),
                            if (l != null) Text(bands![i].formatBandFrequency),
                          ],
                        );
                      }),
                ),
              ).toList(),
            ],
          );
        },
      );
    });
  }
}

class VerticalSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;

  const VerticalSlider({
    Key? key,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.fitHeight,
      alignment: Alignment.bottomCenter,
      child: Transform.rotate(
        angle: -pi / 2,
        child: Container(
          width: 400.0,
          height: 400.0,
          alignment: Alignment.center,
          child: SliderTheme(
            data: const SliderThemeData(
              trackHeight: 3,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 16),
              tickMarkShape: RoundSliderTickMarkShape(tickMarkRadius: 2),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
  }
}

class ControlButtons extends StatelessWidget {
  final AudioPlayer player;

  const ControlButtons(this.player, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (context, snapshot) {
            final playerState = snapshot.data;
            final processingState = playerState?.processingState;
            final playing = playerState?.playing;
            if (processingState == ProcessingState.loading ||
                processingState == ProcessingState.buffering) {
              return Container(
                margin: const EdgeInsets.all(8.0),
                width: 64.0,
                height: 64.0,
                child: const CircularProgressIndicator(),
              );
            } else if (playing != true) {
              return MaterialButton(
                onPressed: player.play,
                color: Colors.white,
                textColor: const Color(0xFF0B1220),
                padding: const EdgeInsets.all(16),
                shape: const CircleBorder(),
                elevation: 0.0,
                child: const Icon(Icons.play_arrow, size: 32),
              );
            } else if (processingState != ProcessingState.completed) {
              return MaterialButton(
                onPressed: player.pause,
                color: Colors.white,
                textColor: const Color(0xFF0B1220),
                padding: const EdgeInsets.all(16),
                shape: const CircleBorder(),
                elevation: 0.0,
                child: const Icon(Icons.pause, size: 32),
              );
            } else {
              return IconButton(
                icon: const Icon(Icons.replay),
                iconSize: 64.0,
                onPressed: () => player.seek(Duration.zero),
              );
            }
          },
        ),
      ],
    );
  }
}
