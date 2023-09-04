// This example demonstrates Android audio effects.
//
// To run:
//
// flutter run -t lib/example_effects.dart

import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:eq_app/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'package:rxdart/rxdart.dart';

import 'Channel.dart';

class MyApp extends StatefulWidget {
  final AudioPlayer player;
  final AndroidLoudnessEnhancer loudnessEnhancer;
  final AndroidEqualizer equalizer;
  const MyApp(
      {Key? key,
      required this.player,
      required this.loudnessEnhancer,
      required this.equalizer})
      : super(key: key);

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    ambiguate(WidgetsBinding.instance)!.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
    ));
    // _init();
  }

  // Future<void> _init() async {
  //   final session = await AudioSession.instance;
  //   await session.configure(const AudioSessionConfiguration.speech());
  //   try {
  //     await widget.player.setAudioSource(AudioSource.uri(Uri.parse(
  //         "https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3")));
  //   } catch (e) {
  //     print("Error loading audio source: $e");
  //   }
  // }

  @override
  void dispose() {
    ambiguate(WidgetsBinding.instance)!.removeObserver(this);
    widget.player.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Release the player's resources when not in use. We use "stop" so that
      // if the app resumes later, it will still remember what position to
      // resume from.
      widget.player.stop();
    }
  }

  Stream<PositionData> get _positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
          widget.player.positionStream,
          widget.player.bufferedPositionStream,
          widget.player.durationStream,
          (position, bufferedPosition, duration) => PositionData(
              position, bufferedPosition, duration ?? Duration.zero));

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              StreamBuilder<bool>(
                stream: widget.loudnessEnhancer.enabledStream,
                builder: (context, snapshot) {
                  final enabled = snapshot.data ?? false;
                  return SwitchListTile(
                    title: const Text('Loudness Enhancer'),
                    value: enabled,
                    onChanged: widget.loudnessEnhancer.setEnabled,
                  );
                },
              ),
              LoudnessEnhancerControls(
                  loudnessEnhancer: widget.loudnessEnhancer),
              StreamBuilder<bool>(
                stream: widget.equalizer.enabledStream,
                builder: (context, snapshot) {
                  final enabled = snapshot.data ?? false;
                  return SwitchListTile(
                    title: const Text('Equalizer'),
                    value: enabled,
                    onChanged: widget.equalizer.setEnabled,
                  );
                },
              ),

              // ControlButtons(widheyplayer),
              StreamBuilder<PositionData>(
                stream: _positionDataStream,
                builder: (context, snapshot) {
                  final positionData = snapshot.data;
                  return SeekBar(
                    duration: positionData?.duration ?? Duration.zero,
                    position: positionData?.position ?? Duration.zero,
                    bufferedPosition:
                        positionData?.bufferedPosition ?? Duration.zero,
                    onChangeEnd: widget.player.seek,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoudnessEnhancerControls extends StatelessWidget {
  final AndroidLoudnessEnhancer loudnessEnhancer;

  const LoudnessEnhancerControls({
    Key? key,
    required this.loudnessEnhancer,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: loudnessEnhancer.targetGainStream,
      builder: (context, snapshot) {
        final targetGain = snapshot.data ?? 0.0;
        return Slider(
          min: -3.0,
          max: 3.0,
          value: targetGain,
          onChanged: loudnessEnhancer.setTargetGain,
          label: 'foo',
        );
      },
    );
  }
}

class EqualizerControls extends StatefulWidget {
  const EqualizerControls({Key? key}) : super(key: key);

  @override
  State<EqualizerControls> createState() => _EqualizerControlsState();
}

class _EqualizerControlsState extends State<EqualizerControls> {
  List<int> bandValues = [0, 0, 0, 0, 0];
  @override
  Widget build(BuildContext context) {
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
                        bandValues[i] = l;
                      }
                      return Column(
                        children: [
                          Text("${bandValues[i]} Hz"),
                          StreamBuilder<List<int>>(
                              stream: Stream.fromFuture(
                                  Channel.getBandLevelRange()),
                              builder: (context, bandLevel) {
                                return SizedBox(
                                  width: MediaQuery.of(context).size.width,
                                  height:
                                      MediaQuery.of(context).size.height / 2.5,
                                  child: VerticalSlider(
                                    min: bandLevel.data?.first.toDouble() ?? 0,
                                    max: bandLevel.data?.last.toDouble() ?? 1.0,
                                    value: level.data?.toDouble() ?? 0,
                                    onChanged: (value) {
                                      setState(() {
                                        bandValues[i] = value.toInt();
                                      });
                                      Channel.setBandLevel(i, value.toInt());
                                    },
                                  ),
                                );
                              }),
                          Text('${bands![i] ~/ 1000} Hz'),
                        ],
                      );
                    }),
              ),
            ).toList(),
          ],
        );
      },
    );
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
