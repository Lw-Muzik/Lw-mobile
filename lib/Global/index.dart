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
import '../pages/Equalizer.dart';
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

Widget playerActionBar(AppController controller, BuildContext context) {
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 24),
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ActionItem(
          icon: Icons.equalizer_rounded,
          label: 'EQ',
          onTap: () =>
              Routes.routeTo(const Equalizer(), context, animate: true),
        ),
        _ActionItem(
          icon: Icons.graphic_eq_rounded,
          label: 'Visual',
          onTap: () => Routes.routeTo(const VisualUI(), context),
        ),
        _ActionItem(
          icon: Icons.queue_music_rounded,
          label: 'Queue',
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              barrierColor: Colors.black54,
              builder: (context) {
                return DraggableScrollableSheet(
                  initialChildSize: 0.55,
                  minChildSize: 0.3,
                  maxChildSize: 0.92,
                  builder: (context, scrollController) {
                    return NowPlaying(
                      controller: controller,
                      scrollController: scrollController,
                    );
                  },
                );
              },
            );
          },
        ),
        _ActionItem(
          icon: Icons.info_outline_rounded,
          label: 'Info',
          onTap: () => showTrackInfo(context, controller),
        ),
      ],
    ),
  );
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget playerCard(
  Animation<double> animation,
  BuildContext context,
  AppController controller, {
  int? songIndex,
}) {
  final idx = songIndex ?? controller.songId;
  if (idx < 0 || idx >= controller.songs.length) return const SizedBox.shrink();
  final song = controller.songs[idx];

  return Align(
    alignment: const Alignment(0, -0.15),
    child: AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Transform.scale(
          scale: animation.value,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
              child: AspectRatio(
                aspectRatio: 1.0,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: ArtworkWidget(
                      quality: 100,
                      borderRadius: BorderRadius.circular(18),
                      size: 1000,
                      songId: song.id,
                      type: ArtworkType.AUDIO,
                      path: song.data,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
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
                controller.playSongFromList(s, 0);
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
