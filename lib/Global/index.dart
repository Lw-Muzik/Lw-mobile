import 'dart:ui';
import 'package:eq_app/Helpers/VisualizerWidget.dart';
import 'package:eq_app/Helpers/index.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import '/exports/exports.dart';

import '../Helpers/AudioHandler.dart';
import '../Helpers/Files.dart';
import '../Routes/routes.dart';
import '../Visualizers/MultiwaveVisualizer.dart';
import '../controllers/AppController.dart';
import '../pages/VisualUI.dart';
import '../player/widgets/NowPlaying.dart';
import '../player/widgets/TrackInfo.dart';
import '../widgets/ArtworkWidget.dart';

SystemUiOverlayStyle overlay = const SystemUiOverlayStyle(
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarContrastEnforced: false,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.transparent,
);
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
                color: Theme.of(context).primaryColorLight.withValues(alpha: 0.1),
                waveData: fft,
                // width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
              ),
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
        IconButton(
          style: IconButton.styleFrom(backgroundColor: Colors.black54),
          onPressed: () => Routes.routeTo(const VisualUI(), context),
          icon: const Icon(Icons.graphic_eq_rounded),
        ),
        IconButton(
          style: IconButton.styleFrom(backgroundColor: Colors.black54),
          onPressed: () {
            showCupertinoModalPopup(
              barrierColor: Colors.black12,
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              context: context,
              builder: (context) {
                return BottomSheet(
                  backgroundColor: Colors.black38,
                  onClosing: () {},
                  builder: (context) {
                    return NowPlaying(controller: controller);
                  },
                );
              },
            );
          },
          icon: const Icon(Icons.playlist_play),
        ),
        IconButton(
          style: IconButton.styleFrom(backgroundColor: Colors.black54),
          onPressed: () => showTrackInfo(context, controller),
          color: Colors.white,
          icon: const Icon(Icons.more_vert_rounded),
        ),
      ],
    ),
  );
}

Widget playerCard(
  Animation<double> animation,
  BuildContext context,
  AppController controller, {
  int? songIndex,
}) {
  final idx = songIndex ?? controller.songId;
  final song = controller.songs[idx];
  return Stack(
    children: [
      AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          return Transform.scale(
            scale: animation.value,
            child: FittedBox(
              child: Padding(
                padding: const EdgeInsets.only(
                  right: 28.0,
                  top: 10,
                  bottom: 0,
                  left: 28,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.width,
                  width: MediaQuery.of(context).size.width,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ArtworkWidget(
                          quality: 100,
                          borderRadius: BorderRadius.circular(15),
                          size: 1000,
                          songId: song.id,
                          type: ArtworkType.AUDIO,
                          path: song.data,
                        ),
                        // Gradient overlay at bottom for text legibility
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 120,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.7),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Title + artist overlay
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 52,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium!
                                    .copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                song.artist ?? 'Unknown artist',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall!
                                    .copyWith(
                                      color: Colors.white.withValues(alpha: 0.7),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      if (idx == controller.songId)
        Positioned(
          bottom: 0,
          left: 20,
          right: 20,
          child: playerControls(controller, context),
        ),
    ],
  );
}

Decoration commonDeration(
  AppController controller,
  int listIndex,
  BuildContext context,
) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(10),
    color: controller.songId == listIndex && controller.handler.player.playing
        ? Theme.of(context).brightness == Brightness.light
              ? Theme.of(context).primaryColor.withValues(alpha: 0.41)
              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.31)
        : null,
  );
}

Widget folderArtwork(String path, String title) {
  return FutureBuilder<List<SongModel>>(
    future: Files.queryFromFolder(path),
    builder: (context, snapshot) {
      var data = snapshot.data;
      return snapshot.hasData
          ? Stack(
              children: [
                ArtworkWidget(
                  quality: 50,
                  size: 200,
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
                  bottom: -10,
                  child: Card(
                    margin: const EdgeInsets.all(10),
                    color: Theme.of(context).primaryColorDark.withValues(alpha: 0.7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: "$title \n",
                            style: Theme.of(
                              context,
                            ).textTheme.labelSmall!.apply(color: Colors.white),
                          ),
                          TextSpan(
                            text: "${data.length} Songs",
                            style: Theme.of(context).textTheme.labelSmall!
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
    },
  );
}

Widget headerWidget(
  AppController controller,
  BuildContext context, {
  List<SongModel>? data,
  Widget? child,
}) {
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
          child: GestureDetector(
            onTap: () {
              List<SongModel> s = data;
              if (s.isNotEmpty) {
                controller.songs.clear();
                controller.songs = s;
                controller.songId = 0;

                loadAudioSource(controller.handler, s[0]);
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
        ),
    ],
  );
}

void loadAudioSource(HypeAudioHandler handler, SongModel song, {bool replayGain = false}) async {
  String image = await fetchArtworkUrl(song.data, song.id);

  MediaItem item = MediaItem(
    id: song.data,
    album: song.album,
    title: song.title,
    artist: song.artist,
    duration: Duration(milliseconds: song.duration ?? 0),
    artUri: Uri.file(image),
  );

  handler.setCurrentMediaItem(item);
  await handler.player.setAudioSource(AudioSource.uri(Uri.parse(item.id), tag: item));

  if (replayGain) {
    final gain = await HypeAudioHandler.computeReplayGainVolume(song.data);
    handler.player.setVolume(gain);
  } else {
    handler.player.setVolume(1.0);
  }

  handler.player.play();
}

//  function to show track info
void showTrackInfo(BuildContext context, AppController controller) {
  showCupertinoModalPopup(
    barrierColor: Colors.transparent,
    context: context,
    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
    builder: (context) {
      return TrackInfoWidget(controller: controller);
    },
  );
}
