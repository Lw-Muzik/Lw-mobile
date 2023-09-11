import 'dart:ui';

import 'package:eq_app/Helpers/VisualizerWidget.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../Routes/routes.dart';
import '../Visualizers/MultiwaveVisualizer.dart';
import '../controllers/AppController.dart';
import '../pages/VisualUI.dart';
import '../player/widgets/NowPlaying.dart';
import '../player/widgets/PlayerSettings.dart';
import '../widgets/ArtworkWidget.dart';

SystemUiOverlayStyle overlay = const SystemUiOverlayStyle(
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent);
PreferredSizeWidget kAppBar = AppBar(
  toolbarHeight: 0,
  systemOverlayStyle: overlay,
  forceMaterialTransparency: true,
);

Widget playerVisual(AppController controller) {
  return StreamBuilder(
      stream: controller.audioPlayer.androidAudioSessionIdStream,
      builder: (context, session) {
        return session.hasData
            ? VisualizerWidget(
                builder: (context, fft, rate) {
                  return fft.isNotEmpty
                      ? CustomPaint(
                          painter: MultiWaveVisualizer(
                              color: Theme.of(context)
                                  .primaryColorLight
                                  .withOpacity(0.1),
                              waveData: fft,
                              // width: MediaQuery.of(context).size.width,
                              height: MediaQuery.of(context).size.height),
                          child: const Center(),
                        )
                      : Container();
                },
                id: session.data ?? 0,
              )
            : Container();
      });
}

Widget playerControls(AppController controller, BuildContext context) {
  return Padding(
    padding: const EdgeInsets.only(right: 20.0, top: 10, bottom: 10, left: 20),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton.filledTonal(
          color: Colors.white,
          onPressed: () => Routes.routeTo(const VisualUI(), context),
          icon: const Icon(Icons.graphic_eq_rounded),
        ),
        IconButton.filledTonal(
            color: Colors.white,
            onPressed: () {
              showCupertinoModalPopup(
                barrierColor: Colors.black12,
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                context: context,
                builder: (context) {
                  return BottomSheet(
                    backgroundColor: Colors.black26,
                    onClosing: () {},
                    builder: (context) {
                      return NowPlaying(
                        controller: controller,
                      );
                    },
                  );
                },
              );
            },
            icon: const Icon(Icons.playlist_play)),
        IconButton.filledTonal(
          onPressed: () => showModalBottomSheet(
            context: context,
            builder: (context) {
              return BottomSheet(
                onClosing: () {},
                builder: (context) {
                  return PlayerSettings(
                    controller: controller,
                  );
                },
              );
            },
          ),
          color: Colors.white,
          icon: const Icon(Icons.more_vert_rounded),
        )
      ],
    ),
  );
}

Widget playerCard(Animation<double> animation, BuildContext context,
    AppController controller) {
  return Stack(
    children: [
      AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Transform.scale(
              scale: animation.value,
              child: Padding(
                padding: const EdgeInsets.only(
                    right: 28.0, top: 10, bottom: 0, left: 28),
                child: SizedBox(
                  height: MediaQuery.of(context).size.width,
                  width: MediaQuery.of(context).size.width,
                  child: ArtworkWidget(
                    quality: 100,
                    borderRadius: BorderRadius.circular(15),
                    size: 1000,
                    songId: controller.songs[controller.songId].id,
                    type: ArtworkType.AUDIO,
                    path: controller.songs[controller.songId].data,
                  ),
                ),
              ),
            );
          }),
      Positioned(
          bottom: -10,
          left: 0,
          right: 0,
          child: playerControls(controller, context)),
    ],
  );
}

Decoration commonDeration(
    AppController controller, int listIndex, BuildContext context) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(50),
    color: controller.songId == listIndex && controller.audioPlayer.playing
        ? Theme.of(context).brightness == Brightness.light
            ? Theme.of(context).primaryColor.withOpacity(0.1)
            : Theme.of(context).primaryColorLight.withOpacity(0.31)
        : null,
  );
}

foldersArtwork() {
  // QueryArtworkWidget(
  //   artworkBorder: BorderRadius.circular(10),
  //   format: ArtworkFormat.PNG,
  //   size: 500,
  //   id: item.data![index].id,
  //   nullArtworkWidget: ClipRRect(
  //     borderRadius: BorderRadius.circular(10),
  //     child: Image.asset("assets/audio.jpeg"),
  //   ),
  //   type: ArtworkType.ARTIST,
  // );
}

headerWidget(
    AppController controller, BuildContext context, List<SongModel> data) {
  return Stack(
    children: [
      ArtworkWidget(
        quality: 100,
        size: 3000,
        borderRadius: BorderRadius.zero,
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        songId: data[data.length > 1 ? data.length - 1 : 0].id,
        type: ArtworkType.AUDIO,
        path: data[data.length > 1 ? data.length - 1 : 0].data,
      ),
      Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black26,
              Colors.black38,
              Colors.black45,
              Colors.black54,
              Colors.black87,
              Colors.black,
            ],
          ),
        ),
      ),
      Positioned(
        bottom: 160,
        left: 10,
        child: InkWell(
          onTap: () {
            List<SongModel> s = data;
            if (s.isNotEmpty) {
              s.forEach((element) {
                print(element.data);
              });
              controller.songs.clear();
              controller.songs = s;
              controller.songId = 0;
              controller.audioPlayer.setUrl(s[0].data);
              controller.audioPlayer.play();
            }
          },
          child: Card(
            child: Row(
              children: [
                Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Play All",
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.play_circle_sharp, size: 35),
                ),
              ],
            ),
          ),
        ),
      )
    ],
  );
}
