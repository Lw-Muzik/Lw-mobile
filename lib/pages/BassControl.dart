import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) {
    return Column(
      children: [
        StreamBuilder<bool>(
            stream: Stream.fromFuture(Channel.isBassEnabled()),
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
                    });
                    Channel.enableBass(value);
                    Channel.enableVirtualizer(value);
                    Channel.enableLoudnessEnhancer(value);
                  });
            }),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StreamBuilder<int>(
                  stream: Stream.fromFuture(Channel.getBassStrength()),
                  builder: (context, strength) {
                    int? b = strength.data;
                    if (b != null) {
                      bass = b.toDouble();
                    }
                    return RoundSlider(
                        title: "BassBoost",
                        dB: double.parse(bass.toStringAsFixed(1)),
                        value: bass,
                        max: 1000,
                        width: 120,
                        height: 120,
                        min: 0,
                        onChanged: (strength) {
                          setState(() {
                            bass = strength;
                          });
                          Channel.setBassStrength(strength.toInt());
                        });
                  }),
              StreamBuilder<int>(
                  stream: Stream.fromFuture(Channel.getVirtualizerStrength()),
                  builder: (context, virtualizer) {
                    int? v = virtualizer.data;
                    if (v != null) {
                      stereo = v.toDouble();
                    }
                    return RoundSlider(
                        title: "Virtualizer",
                        dB: double.parse(bass.toStringAsFixed(1)),
                        value: stereo,
                        max: 1000,
                        width: 120,
                        height: 120,
                        min: 0,
                        onChanged: (s) {
                          setState(() {
                            stereo = s;
                          });
                          Channel.setVirtualizerStrength(s.toInt());
                        });
                  }),
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
