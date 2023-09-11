import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../Helpers/VisualizerWidget.dart';
import '../Visualizers/MultiwaveVisualizer.dart';
import '../controllers/AppController.dart';

class PlayerBody extends StatefulWidget {
  final AppController controller;
  final Widget child;
  const PlayerBody({super.key, required this.controller, required this.child});

  @override
  State<PlayerBody> createState() => _PlayerBodyState();
}

class _PlayerBodyState extends State<PlayerBody> {
  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, state) {
        return Stack(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height,
              child: QueryArtworkWidget(
                  artworkBlendMode: BlendMode.darken,
                  artworkBorder: BorderRadius.zero,
                  artworkHeight: MediaQuery.of(context).size.height,
                  artworkWidth: MediaQuery.of(context).size.width,
                  id: controller.songs[controller.songId].id,
                  format: ArtworkFormat.PNG,
                  nullArtworkWidget: Image.asset(
                    "assets/audio.jpeg",
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                  ),
                  size: 2000,
                  type: ArtworkType.AUDIO),
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
                      const Color.fromARGB(255, 0, 0, 0).withOpacity(0.50),
                      const Color.fromARGB(255, 0, 0, 0).withOpacity(0.80)
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.50, 1.0],
                  ),
                ),
              ),
            ),
            widget.child,
          ],
        );
      },
    );
  }
}
