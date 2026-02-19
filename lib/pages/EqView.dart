import 'dart:ui';

import 'package:provider/provider.dart';
import '../Helpers/Eq.dart';
import '../controllers/AppController.dart';
import '/widgets/EqPresets.dart';
import 'package:flutter/material.dart';
import 'BassControl.dart';
import '../Helpers/Channel.dart';

class EqView extends StatefulWidget {
  const EqView({super.key});

  @override
  State<EqView> createState() => _EqViewState();
}

class _EqViewState extends State<EqView> {
  bool eq = false;

  @override
  Widget build(BuildContext context) {
    final appController = context.watch<AppController>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0),
      child: FittedBox(
        fit: BoxFit.fitWidth,
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          child: Column(
            children: [
              const SizedBox(height: 34),
              StreamBuilder<bool>(
                stream: Stream.fromFuture(Channel.isEnabled()),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return SwitchListTile(
                      title: const Text("Equalizer"),
                      subtitle: const Text("Error"),
                      value: eq,
                      onChanged: null,
                    );
                  }
                  eq = snapshot.data ?? false;
                  return SwitchListTile(
                    title: const Text("Equalizer"),
                    subtitle: Text(eq ? "On" : "Off"),
                    value: eq,
                    onChanged: (value) {
                      setState(() => eq = value);
                      appController.enableDSP = value;
                      Channel.enableEq(value);
                      Channel.enableDSPEngine(value);
                    },
                  );
                },
              ),
              const SizedBox(height: 4),
              buildCard(appController),
              buildPresetsLabel(context),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18.0),
                child: EqPresets(),
              ),
              const SizedBox(height: 4),
              const BassControl(),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildCard(AppController appController) {
    return Card(
      clipBehavior: Clip.hardEdge,
      color: appController.isFancy
          ? Colors.transparent
          : Theme.of(context).cardColor,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: appController.isFancy ? 40 : 0,
          sigmaY: appController.isFancy ? 40 : 0,
        ),
        child: const EqualizerControls(),
      ),
    );
  }

  Widget buildPresetsLabel(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          "Presets",
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}
