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
    ebass = context.read<AppController>().enableEffects;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildEffectsSwitch(),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              const SizedBox(width: 10),
              _buildSlider(
                title: "Virtualizer",
                stream: Stream.fromFuture(Channel.getVirtualizerStrength()),
                value: stereo,
                max: 1000,
                onChanged: (value) {
                  stereo = value;
                  Channel.setVirtualizerStrength(value.toInt());
                },
              ),
              const SizedBox.square(dimension: 10),
              _buildSlider(
                title: "Vocal Boost",
                stream: Stream.fromFuture(Channel.getTargetGain()),
                value: tGain,
                max: 1000,
                onChanged: (value) {
                  tGain = value;
                  Channel.setTargetGain(value.toInt());
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEffectsSwitch() {
    return StreamBuilder<bool>(
      stream: Stream.fromFuture(Channel.getVirtualizerEnabled()),
      builder: (context, snapshot) {
        ebass = snapshot.data ?? ebass;
        return SwitchListTile.adaptive(
          title: const Text("Effects"),
          subtitle: Text(ebass ? "enabled" : "disabled"),
          value: ebass,
          onChanged: (value) {
            setState(() {
              ebass = value;
              context.read<AppController>().enableEffects = ebass;
            });
            Channel.enableVirtualizer(value);
            Channel.enableLoudnessEnhancer(value);
          },
        );
      },
    );
  }

  Widget _buildSlider({
    required String title,
    required Stream<dynamic> stream,
    required double value,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return StreamBuilder<dynamic>(
      stream: stream,
      builder: (context, snapshot) {
        double sliderValue = snapshot.data?.toDouble() ?? value;
        return RoundSlider(
          title: title,
          dB: double.parse((sliderValue / max * 100).toStringAsFixed(1)),
          value: sliderValue,
          max: max,
          width: 120,
          height: 120,
          min: 0,
          onChanged: ebass
              ? (value) {
                  setState(() {
                    onChanged(value);
                  });
                }
              : (x) {},
        );
      },
    );
  }
}
