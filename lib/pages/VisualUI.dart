import 'dart:developer';

import 'package:eq_app/Helpers/AudioVisualizer.dart';
import 'package:eq_app/Visualizers/CircularBarVisualizer.dart';
import 'package:eq_app/controllers/AppController.dart';
import 'package:eq_app/player/widgets/MusicInfo.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Helpers/VisualizerWidget.dart';
import '../Routes/routes.dart';
import '../widgets/Body.dart';

class VisualUI extends StatefulWidget {
  const VisualUI({super.key});

  @override
  State<VisualUI> createState() => _VisualUIState();
}

class _VisualUIState extends State<VisualUI> {
  bool isEnabled = false;
  @override
  Widget build(BuildContext context) {
    Visualizers.setFrameRate(1);
    Visualizers.scaleVisualizer(true);

    Visualizers.getEnabled().asStream().listen((v) {});
    return Body(
      child: Consumer<AppController>(
        builder: (context, controller, child) {
          if (controller.visuals) {
            Visualizers.enableVisual(true);
            // Visualizers.scaleVisualizer(!controller.visuals);
          }
          return Scaffold(
            backgroundColor: controller.isFancy
                ? Colors.transparent
                : Theme.of(context).scaffoldBackgroundColor,
            body: InkWell(
              onTap:()=>Routes.pop(context),
              child: Column(
                children: [
                  mounted
                      ? VisualizerWidget(
                          builder: (context, fft, x) {
                            return CustomPaint(
                              painter: CircularBarVisualizer(
                                  color: Colors.white,
                                  waveData: fft,
                                  width: MediaQuery.of(context).size.width,
                                  height: MediaQuery.of(context).size.height),
                              child: const Center(),
                            );
                          },
                          id: 0,
                        )
                      : Container(),
                ],
              ),
            ),
            floatingActionButton:
                SizedBox(height: 140, child: MusicInfo(controller: controller)),
          );
        },
      ),
    );
  }
}
