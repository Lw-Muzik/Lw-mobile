import 'dart:ui';

import 'package:provider/provider.dart';

import '../controllers/AppController.dart';
import '/widgets/EqPresets.dart';
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
  int selected = 0;
  bool eq = false;
  bool ebass = false;
  List<double> bandValues = [0, 0, 0, 0, 0];
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10.0, right: 10.0),
      child: FittedBox(
        fit: BoxFit.fitWidth,
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          child: Flex(
            direction: Axis.vertical,
            children: [
              const SizedBox(
                height: 34,
              ),
              StreamBuilder<bool>(
                  stream: Stream.fromFuture(Channel.isEnabled()),
                  builder: (context, snapshot) {
                    eq = snapshot.data ?? false;
                    return SwitchListTile(
                      title: const Text("Equalizer"),
                      subtitle: Text(eq ? "On" : "Off"),
                      value: snapshot.data ?? eq,
                      onChanged: (value) {
                        setState(() {
                          Provider.of<AppController>(context, listen: false)
                              .enableDSP = value;
                        });
                        Channel.enableEq(value);
                        setState(() {});
                        Channel.enableDSPEngine(value);
                        setState(() {});
                      },
                    );
                  }),
              const SizedBox(
                height: 4,
              ),
              Card(
                clipBehavior: Clip.hardEdge,
                color: context.watch<AppController>().isFancy
                    ? Colors.transparent
                    : Theme.of(context).cardColor,
                elevation: 0,
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                child: BackdropFilter(
                    filter: context.watch<AppController>().isFancy
                        ? ImageFilter.blur(sigmaX: 40, sigmaY: 40)
                        : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                    child: const EqualizerControls()),
              ),
              Padding(
                padding: const EdgeInsets.all(18.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Presets",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 18.0, right: 18.0),
                child: EqPresets(),
              ),
              const SizedBox(
                height: 4,
              ),
              const BassControl(),
              const SizedBox(
                height: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
