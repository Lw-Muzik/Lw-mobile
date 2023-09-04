import 'dart:developer';

import 'package:flutter/material.dart';

import 'BassControl.dart';
import '../Helpers/Channel.dart';
import '../Helpers/Eq.dart';

class EqView extends StatefulWidget {
  const EqView({super.key});

  @override
  State<EqView> createState() => _EqViewState();
}

class _EqViewState extends State<EqView> {
  double bass = 0;
  bool eq = false;
  bool ebass = false;
  List<double> bandValues = [0, 0, 0, 0, 0];
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        StreamBuilder<bool>(
            stream: Stream.fromFuture(Channel.isEnabled()),
            builder: (context, snapshot) {
              eq = snapshot.data ?? false;
              return SwitchListTile(
                title: const Text("Equalizer"),
                subtitle: Text(eq ? "On" : "Off"),
                value: snapshot.data ?? eq,
                onChanged: (value) {
                  setState(() {});
                  Channel.enableEq(value);
                },
              );
            }),
        const SizedBox(
          height: 4,
        ),
        const EqualizerControls(),
        const SizedBox(
          height: 4,
        ),
        const BassControl(),
      ],
    );
  }
}
