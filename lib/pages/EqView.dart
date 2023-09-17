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
      child: SingleChildScrollView(
        child: Flex(
          direction: Axis.vertical,
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
            const EqualizerControls(),
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
            const EqPresets(),
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
    );
  }
}
