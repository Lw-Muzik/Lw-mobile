import 'dart:ui';

import 'package:eq_app/controllers/AppController.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../Helpers/VisualizerWidget.dart';
import '../Visualizers/CircularBarVisualizer.dart';
import 'ArtworkWidget.dart';

class Body extends StatelessWidget {
  final Widget child;
  const Body({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(builder: (context, controller, x) {
      return Stack(
        children: [
          if (controller.songs.isNotEmpty)
            SizedBox(
              height: MediaQuery.of(context).size.height,
              child: ArtworkWidget(
                useSaved: true,
                path: controller.songs[controller.songId].data,
                size: controller.bgQuality.toInt(),
                quality: 1,
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                songId: controller.songs[controller.songId].id,
                type: ArtworkType.AUDIO,
              ),
            ),
          BackdropFilter(
            filter: ImageFilter.blur(
                sigmaX: controller.blur, sigmaY: controller.blur),
            child: Container(
              height: MediaQuery.of(context).size.height,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color.fromARGB(255, 0, 0, 0).withOpacity(0.2),
                    const Color.fromARGB(255, 0, 0, 0).withOpacity(0.30),
                    const Color.fromARGB(255, 0, 0, 0).withOpacity(0.50)
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.50, 1.0],
                ),
              ),
            ),
          ),
          if (controller.songs.isNotEmpty &&
              controller.isVisualInBackground == false)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 200, sigmaY: 200),
              child: Container(
                height: MediaQuery.of(context).size.height,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color.fromARGB(255, 0, 0, 0).withOpacity(0.2),
                      const Color.fromARGB(255, 0, 0, 0).withOpacity(0.3),
                      const Color.fromARGB(255, 0, 0, 0).withOpacity(0.4)
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.2, 0.5, 1],
                  ),
                ),
              ),
            ),
          if (controller.isVisualInBackground)
            VisualizerWidget(
              builder: (context, fft, rate) {
                return CustomPaint(
                  painter: CircularBarVisualizer(
                      color:
                          Theme.of(context).primaryColorLight.withOpacity(0.1),
                      waveData: fft,
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.height),
                  child: const Center(),
                );
              },
              id: 0,
            ),
          Container(
            decoration: const BoxDecoration(
              backgroundBlendMode: BlendMode.colorBurn,
              color: Colors.black12,
            ),
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: child,
          ),
        ],
      );
    });
  }
}
