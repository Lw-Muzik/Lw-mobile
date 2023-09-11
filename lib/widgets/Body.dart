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
    var controller = Provider.of<AppController>(context, listen: true);
    return Stack(
      children: [
        if (controller.songs.isNotEmpty)
          SizedBox(
            height: MediaQuery.of(context).size.height,
            child: ArtworkWidget(
              useSaved: false,
              size: controller.bgQuality.toInt(),
              quality: 1,
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              songId: controller.songs[controller.songId].id,
              type: ArtworkType.AUDIO,
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
          StreamBuilder(
              stream: controller.audioPlayer.androidAudioSessionIdStream,
              builder: (context, session) {
                return session.hasData
                    ? VisualizerWidget(
                        builder: (context, fft, rate) {
                          return CustomPaint(
                            painter: CircularBarVisualizer(
                                color: Theme.of(context)
                                    .primaryColorLight
                                    .withOpacity(0.1),
                                waveData: fft,
                                width: MediaQuery.of(context).size.width,
                                height: MediaQuery.of(context).size.height),
                            child: const Center(),
                          );
                        },
                        id: session.data ?? 0,
                      )
                    : Container();
              }),
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
  }
}
