import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:eq_app/Helpers/AudioHandler.dart';
import 'package:eq_app/Helpers/VisualizerWidget.dart';
import 'package:eq_app/Helpers/index.dart';
import 'package:eq_app/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../Helpers/Files.dart';
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
  return VisualizerWidget(
    builder: (context, fft, rate) {
      return fft.isNotEmpty
          ? CustomPaint(
              painter: MultiWaveVisualizer(
                  color: Theme.of(context).primaryColorLight.withOpacity(0.1),
                  waveData: fft,
                  // width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height),
              child: const Center(),
            )
          : Container();
    },
    id: 0,
  );
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
    borderRadius: BorderRadius.circular(10),
    color: controller.songId == listIndex && controller.audioHandler.playing
        ? Theme.of(context).brightness == Brightness.light
            ? Theme.of(context).primaryColor.withOpacity(0.41)
            : Theme.of(context).colorScheme.primary.withOpacity(0.31)
        : null,
  );
}

Widget folderArtwork(String path, String title) {
  return StreamBuilder<List<SongModel>>(
      stream: Stream.fromFuture(Files.queryFromFolder(path)),
      builder: (context, snapshot) {
        var data = snapshot.data;
        return snapshot.hasData
            ? Stack(
                children: [
                  ArtworkWidget(
                    quality: 100,
                    size: 3000,
                    useSaved: data!.isNotEmpty,
                    borderRadius: BorderRadius.circular(10),
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.width,
                    songId: data[data.length > 2 ? data.length - 2 : 0].id,
                    type: ArtworkType.AUDIO,
                    path: data[data.length > 2 ? data.length - 2 : 0].data,
                  ),
                  Positioned(
                    right: 0,
                    left: 0,
                    bottom: 0,
                    child: Card(
                      margin: const EdgeInsets.all(10),
                      color: Theme.of(context).cardColor.withOpacity(0.7),
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: "$title \n",
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium!
                                  .apply(
                                    color: Colors.white,
                                  ),
                            ),
                            TextSpan(
                              text: "${data.length} Songs",
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge!
                                  .apply(
                                    color: Theme.of(context).primaryColorLight,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Container();
      });
}

Widget headerWidget(AppController controller, BuildContext context,
    {List<SongModel>? data, Widget? child}) {
  return Stack(
    children: [
      child ??
          ArtworkWidget(
            quality: 100,
            size: 3000,
            useSaved: data!.isNotEmpty,
            borderRadius: BorderRadius.zero,
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            songId: data[data.length > 2 ? data.length - 2 : 0].id,
            type: ArtworkType.AUDIO,
            path: data[data.length > 2 ? data.length - 2 : 0].data,
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
      if (data != null && data.isNotEmpty)
        Positioned(
          bottom: 160,
          left: 10,
          child: InkWell(
            onTap: () {
              List<SongModel> s = data;
              if (s.isNotEmpty) {
                controller.songs.clear();
                controller.songs = s;
                controller.songId = 0;
                // controller.audioHandler.setUrl(s[0].data);
                // controller.audioHandler.play();
                loadAudioSource(controller.audioHandler, s[0]);
              }
            },
            child: Card(
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      "Play All",
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  const Padding(
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

void loadAudioSource(AudioPlayer audioHandler, SongModel song) async {
  String image = await fetchArtworkUrl(song.data, song.id);
  final player = audioHandler;
  MediaItem item = MediaItem(
    id: song.data,
    album: song.album,
    title: song.title,
    artist: song.artist,
    duration: Duration(milliseconds: song.duration ?? 0),
    artUri: Uri.file(image),
  );

  player.setAudioSource(
      AudioSource.uri(
        Uri.parse(item.id),
        tag: item,
      ),
      initialPosition: Duration.zero);
  // player.setUrl(song.data);

  player.play();
}
