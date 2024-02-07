import 'package:eq_app/controllers/AppController.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Helpers/Channel.dart';
import '../widgets/RoundSlider.dart';

class BassControl extends StatefulWidget {
  const BassControl({super.key});

  @override
  State<BassControl> createState() => _BassControlState();
}

class _BassControlState extends State<BassControl> {
  double bass = 0;
  double stereo = 0;
  double tGain = 0;
  bool eq = false;
  bool ebass = false;
  @override
  void initState() {
    super.initState();
    initEffects();
  }

  initEffects() {
    setState(() {
      ebass = context.read<AppController>().enableEffects;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        StreamBuilder<bool>(
            stream: Stream.fromFuture(Channel.getVirtualizerEnabled()),
            builder: (context, snapshot) {
              bool? enabled = snapshot.data;
              if (enabled != null) {
                ebass = enabled;
              }
              return SwitchListTile.adaptive(
                  title: const Text("Effects"),
                  subtitle: Text(ebass ? "enabled" : "disabled"),
                  value: ebass,
                  onChanged: (value) {
                    setState(() {
                      ebass = !ebass;
                      context.watch<AppController>().enableEffects = ebass;
                    });
                    Channel.enableVirtualizer(value);
                    Channel.enableLoudnessEnhancer(value);
                  });
            }),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // StreamBuilder<double>(
              //     stream: Stream.fromFuture(Channel.getTargetGain()),
              //     builder: (context, strength) {
              //       double? b = strength.data;
              //       if (b != null) {
              //         bass = b;
              //       }
              //       return RoundSlider(
              //           title: "Vocal Boost",
              //           dB: double.parse(((bass / 20) * 100).toStringAsFixed(
              //               1)), //double.parse(bass.toStringAsFixed(1)),
              //           value: bass,
              //           max: 20,
              //           width: 120,
              //           height: 120,
              //           min: 0,
              //           onChanged: ebass == true
              //               ? (strength) {
              //                   setState(() {
              //                     bass = strength;
              //                   });
              //                   Channel.setTargetGain(strength.toInt());
              //                 }
              //               : (x) {});
              //     }),

              const SizedBox(
                width: 10,
              ),
              StreamBuilder<int>(
                  stream: Stream.fromFuture(Channel.getVirtualizerStrength()),
                  builder: (context, virtualizer) {
                    int? v = virtualizer.data;
                    if (v != null) {
                      stereo = v.toDouble();
                    }
                    return RoundSlider(
                        title: "Virtualizer",
                        dB: double.parse(
                            ((stereo / 1000) * 100).toStringAsFixed(1)),
                        value: stereo,
                        max: 1000,
                        width: 120,
                        height: 120,
                        min: 0,
                        onChanged: ebass == true
                            ? (s) {
                                setState(() {
                                  stereo = s;
                                });
                                Channel.setVirtualizerStrength(s.toInt());
                              }
                            : (x) {});
                  }),
              const SizedBox.square(
                dimension: 10,
              ),
              StreamBuilder<double>(
                  stream: Stream.fromFuture(Channel.getTargetGain()),
                  builder: (context, gain) {
                    double? g = gain.data;
                    if (g != null) {
                      tGain = g;
                    }
                    return RoundSlider(
                        title: "Vocal boost",
                        dB: double.parse(bass.toStringAsFixed(1)),
                        value: tGain,
                        max: 1000,
                        width: 120,
                        height: 120,
                        min: 0,
                        onChanged: (s) {
                          setState(() {
                            tGain = s;
                          });
                          Channel.setTargetGain(s.toInt());
                        });
                  }),
            ],
          ),
        ),
      ],
    );
  }
}
