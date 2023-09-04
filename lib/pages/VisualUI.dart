import 'dart:developer';

import 'package:eq_app/Helpers/AudioVisualizer.dart';
import 'package:eq_app/Visualizers/CircularBarVisualizer.dart';
import 'package:eq_app/Visualizers/MultiwaveVisualizer.dart';
import 'package:eq_app/controllers/AppController.dart';
import 'package:eq_app/player/PlayerBody.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Helpers/VisualizerWidget.dart';
import '../Visualizers/BarVisualizer.dart';
import '../Visualizers/LineVisualizer.dart';

class VisualUI extends StatefulWidget {
  const VisualUI({super.key});

  @override
  State<VisualUI> createState() => _VisualUIState();
}

class _VisualUIState extends State<VisualUI> {
  bool isEnabled = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<AppController>(
        builder: (context, controller, child) {
          return PlayerBody(
            controller: controller,
            child: VisualizerWidget(
              builder: (BuildContext context, List<int> fft) {
                return Container(
                  // margin: EdgeInsets.only(
                  //     top: MediaQuery.of(context).size.height / 18),
                  child: CustomPaint(
                    painter: CircularBarVisualizer(
                        color: Colors.white,
                        waveData: fft,
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.height),
                    child: const Center(),
                  ),
                );
              },
              id: controller.audioPlayer.androidAudioSessionId ?? 0,
            ),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: SwitchListTile.adaptive(
          secondary: const Icon(
            Icons.graphic_eq_sharp,
            color: Colors.white70,
            size: 45,
          ),
          title: Text(
            "Visuals",
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.apply(color: Colors.white),
          ),
          subtitle: Text(
            isEnabled ? "Enabled" : "Disabled",
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.apply(color: Colors.white54),
          ),
          value: isEnabled,
          onChanged: (enable) {
            setState(() {
              isEnabled = enable;
            });
            Visualizers.enableVisual(enable);
          }),
    );
  }
}
