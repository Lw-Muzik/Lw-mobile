import 'package:eq_app/Helpers/Channel.dart';
import 'package:eq_app/widgets/HorizontalSlider.dart';
import 'package:flutter/material.dart';

import '../widgets/RoundSlider.dart';

class RoomEffects extends StatefulWidget {
  const RoomEffects({super.key});

  @override
  State<RoomEffects> createState() => _RoomEffectsState();
}

class _RoomEffectsState extends State<RoomEffects> {
  bool isEnabled = false;
  int _decayTime = 200;
  int _reverbLevel = 100;
  int _reflectionD = 0;
  int _density = 100;
  int _reflectionL = 0;
  int _roomLevel = -800;
  int _roomHFLevel = -200;
  int _decayHFLevel = 100;
  int _reverbDecay = 0;
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        StreamBuilder<bool>(
            stream: Stream.fromFuture(Channel.isReverbEnabled()),
            builder: (context, snapshot) {
              bool? enabled = snapshot.data;
              if (enabled != null) {
                isEnabled = enabled;
              }
              return SwitchListTile.adaptive(
                value: isEnabled,
                onChanged: (x) {
                  setState(() {
                    isEnabled = !isEnabled;
                  });
                  Channel.enableReverb(isEnabled);
                },
                title: const Text("Room Effects"),
                subtitle: Text(isEnabled ? "Enabled" : "Disabled"),
              );
            }),
        Padding(
          padding: const EdgeInsets.only(left: 20.0, right: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StreamBuilder<int>(
                  stream: Stream.fromFuture(Channel.getDecayTime()),
                  builder: (context, decayTime) {
                    int? dT = decayTime.data;
                    if (dT != null) {
                      _decayTime = dT;
                    }
                    return RoundSlider(
                      width: 150,
                      height: 150,
                      title: "Decay Time",
                      onChanged: (c) {
                        setState(() {
                          _decayTime = c.toInt();
                        });
                        Channel.setDecayTime(c.toInt());
                      },
                      value: _decayTime.toDouble(),
                      max: 20000,
                      min: 100,
                      dB: _decayTime.toDouble(),
                    );
                  }),
              StreamBuilder<int>(
                  stream: Stream.fromFuture(Channel.getDensity()),
                  builder: (context, density) {
                    int? rL = density.data;
                    if (rL != null) {
                      _density = rL;
                    }
                    return RoundSlider(
                      title: "Density",
                      onChanged: (c) {
                        setState(() {
                          _density = c.toInt();
                        });
                        Channel.setDensity(c.toInt());
                      },
                      value: _density.toDouble(),
                      max: 1000,
                      min: 0,
                      dB: _density.toDouble(),
                      width: 150,
                      height: 150,
                    );
                  }),
            ],
          ),
        ),
        // reverb level
        const SizedBox(
          height: 30,
        ),
// reflections delay
        Padding(
          padding: const EdgeInsets.only(left: 20.0, right: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StreamBuilder<int>(
                  stream: Stream.fromFuture(Channel.getReflectionsDelay()),
                  builder: (context, rDelay) {
                    int? rf = rDelay.data;
                    if (rf != null) {
                      _reflectionD = rf;
                    }
                    return RoundSlider(
                      title: "Reflection Delay",
                      onChanged: (c) {
                        setState(() {
                          _reflectionD = c.toInt();
                        });
                        Channel.setReflectionsDelay(c.toInt());
                      },
                      value: _reflectionD.toDouble(),
                      max: 300,
                      min: 0,
                      dB: _reflectionD.toDouble(),
                      width: 150,
                      height: 150,
                    );
                  }),
              StreamBuilder<int>(
                  stream: Stream.fromFuture(Channel.getReflectionsLevel()),
                  builder: (context, reflectL) {
                    int? rf = reflectL.data;
                    if (rf != null) {
                      _reflectionD = rf;
                    }
                    return RoundSlider(
                      title: "Reflection Level",
                      onChanged: (c) {
                        setState(() {
                          _reflectionL = c.toInt();
                        });
                        Channel.setReflectionsDelayLevel(c.toInt());
                      },
                      value: _reflectionL.toDouble(),
                      max: 1000,
                      min: -9000,
                      dB: _reflectionL.toDouble(),
                      width: 150,
                      height: 150,
                    );
                  }),
            ],
          ),
        ),
        const SizedBox(
          height: 30,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 20.0, right: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StreamBuilder<int>(
                  stream: Stream.fromFuture(Channel.getRoomLevel()),
                  builder: (context, roomLevel) {
                    int? rL = roomLevel.data;
                    if (rL != null) {
                      _roomLevel = rL;
                    }
                    return RoundSlider(
                      width: 150,
                      height: 150,
                      title: "Room Level",
                      onChanged: (c) {
                        setState(() {
                          _roomLevel = c.toInt();
                        });
                        Channel.setRoomLevel(c.toInt());
                      },
                      value: _roomLevel.toDouble(),
                      max: 0,
                      min: -9000,
                      dB: _roomLevel.toDouble(),
                    );
                  }),
              StreamBuilder<int>(
                  stream: Stream.fromFuture(Channel.getRoomHFLevel()),
                  builder: (context, roomHFLevel) {
                    int? rL = roomHFLevel.data;
                    if (rL != null) {
                      _roomLevel = rL;
                    }
                    return RoundSlider(
                      width: 150,
                      height: 150,
                      title: "Room HF Level",
                      onChanged: (c) {
                        setState(() {
                          _roomHFLevel = c.toInt();
                        });
                        Channel.setRoomHFLevel(c.toInt());
                      },
                      value: _roomHFLevel.toDouble(),
                      max: 0,
                      min: -9000,
                      dB: _roomHFLevel.toDouble(),
                    );
                  }),
            ],
          ),
        ),
        const SizedBox(
          height: 30,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 20.0, right: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StreamBuilder<int>(
                  stream: Stream.fromFuture(Channel.getReverbDelay()),
                  builder: (context, reverbDecay) {
                    int? rL = reverbDecay.data;
                    if (rL != null) {
                      _reverbDecay = rL;
                    }
                    return RoundSlider(
                      width: 150,
                      height: 150,
                      title: "Reverb decay",
                      onChanged: (c) {
                        setState(() {
                          _reverbDecay = c.toInt();
                        });
                        Channel.setReverbDelay(c.toInt());
                      },
                      value: _reverbDecay.toDouble(),
                      max: 100,
                      min: 0,
                      dB: _reverbDecay.toDouble(),
                    );
                  }),
              StreamBuilder<int>(
                  stream: Stream.fromFuture(Channel.getDecayHFRatio()),
                  builder: (context, roomHFLevel) {
                    int? rL = roomHFLevel.data;
                    if (rL != null) {
                      _decayHFLevel = rL;
                    }
                    return RoundSlider(
                      width: 150,
                      height: 150,
                      title: "Decay HF Level",
                      onChanged: (c) {
                        setState(() {
                          _decayHFLevel = c.toInt();
                        });
                        Channel.setDecayHFRatio(c.toInt());
                      },
                      value: _decayHFLevel.toDouble(),
                      max: 2000,
                      min: 100,
                      dB: _decayHFLevel.toDouble(),
                    );
                  }),
            ],
          ),
        ),

        // reverb level
        StreamBuilder<int>(
            stream: Stream.fromFuture(Channel.getReverbLevel()),
            builder: (context, reverbLevel) {
              int? rL = reverbLevel.data;
              if (rL != null) {
                _reverbLevel = rL;
              }
              return RoundSlider(
                width: 150,
                height: 150,
                title: "Reverb mix",
                onChanged: (c) {
                  setState(() {
                    _reverbLevel = c.toInt();
                  });
                  Channel.setReverbLevel(c.toInt());
                },
                value: _reverbLevel.toDouble(),
                max: 20000,
                min: -9000,
                dB: _reverbLevel.toDouble(),
              );
            }),
      ],
    );
  }
}
