import 'package:eq_app/widgets/HorizontalSlider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/AppController.dart';

class PlayerSettings extends StatefulWidget {
  final AppController controller;
  const PlayerSettings({super.key, required this.controller});

  @override
  State<PlayerSettings> createState() => _PlayerSettingsState();
}

class _PlayerSettingsState extends State<PlayerSettings> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.width / 1.7,
      child: ListView(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(18.0),
              child: Text(
                "Adjust player UI",
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          // controls
          ExpansionTile(
            title: const Text("Background"),
            children: [
              Consumer<AppController>(builder: (context, control, child) {
                return HorizontalSlider(
                    title: "Blur",
                    onChanged: (x) {
                      control.blur = x;
                    },
                    value: control.blur,
                    max: 500,
                    min: 0,
                    dB: "${((control.blur / 500) * 100).toStringAsFixed(1)} %");
              }),
            ],
          )
        ],
      ),
    );
  }
}
