import 'dart:ui';

import 'package:eq_app/controllers/AppController.dart';
import '/exports/exports.dart';
import '../Helpers/VisualizerWidget.dart';
import '../Visualizers/CircularBarVisualizer.dart';
import 'ArtworkWidget.dart';

class Body extends StatelessWidget {
  final Widget child;
  const Body({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Stack(
      children: [
        // The artwork + full-screen blur layers are the most expensive thing on
        // this screen. They used to sit inside a Consumer<AppController> that
        // rebuilt (and re-configured both BackdropFilters) on EVERY notify —
        // play-count, lyrics-loading, EQ drag, shuffle, etc. _BodyBackground now
        // isolates them behind a Selector + RepaintBoundary so they only rebuild
        // when their actual inputs (artwork, blur amount, visual mode) change.
        const _BodyBackground(),
        // Page content — rebuilds independently of the background.
        Container(
          decoration: const BoxDecoration(
            backgroundBlendMode: BlendMode.colorBurn,
            color: Colors.black12,
          ),
          width: size.width,
          height: size.height,
          child: child,
        ),
      ],
    );
  }
}

/// Selector value for the background — only these fields trigger a rebuild.
typedef _BgData = ({
  bool hasSongs,
  String path,
  int songDbId,
  int bgQuality,
  double blur,
  bool visualInBackground,
});

class _BodyBackground extends StatelessWidget {
  const _BodyBackground();

  @override
  Widget build(BuildContext context) {
    return Selector<AppController, _BgData>(
      selector: (_, c) {
        final hasSongs = c.songs.isNotEmpty;
        final song = hasSongs ? c.songs[c.songId] : null;
        return (
          hasSongs: hasSongs,
          path: song?.data ?? '',
          songDbId: song?.id ?? -1,
          bgQuality: c.bgQuality.toInt(),
          blur: c.blur,
          visualInBackground: c.isVisualInBackground,
        );
      },
      builder: (context, d, _) {
        final size = MediaQuery.of(context).size;
        // A single RepaintBoundary caches the composited background so the page
        // content painting on top of it doesn't force the blur to re-raster.
        return RepaintBoundary(
          child: Stack(
            children: [
              if (d.hasSongs)
                SizedBox(
                  height: size.height,
                  child: ArtworkWidget(
                    useSaved: true,
                    path: d.path,
                    size: d.bgQuality,
                    quality: 1,
                    width: size.width,
                    height: size.height,
                    songId: d.songDbId,
                    type: ArtworkType.AUDIO,
                  ),
                ),
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: d.blur, sigmaY: d.blur),
                child: Container(
                  height: size.height,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color.fromARGB(255, 0, 0, 0).withValues(alpha: 0.2),
                        const Color.fromARGB(255, 0, 0, 0).withValues(alpha: 0.30),
                        const Color.fromARGB(255, 0, 0, 0).withValues(alpha: 0.50),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.50, 1.0],
                    ),
                  ),
                ),
              ),
              if (d.hasSongs && d.visualInBackground == false)
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 200, sigmaY: 200),
                  child: Container(
                    height: size.height,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color.fromARGB(255, 0, 0, 0).withValues(alpha: 0.2),
                          const Color.fromARGB(255, 0, 0, 0).withValues(alpha: 0.3),
                          const Color.fromARGB(255, 0, 0, 0).withValues(alpha: 0.4),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.2, 0.5, 1],
                      ),
                    ),
                  ),
                ),
              if (d.visualInBackground)
                VisualizerWidget(
                  builder: (context, fft, _, rate) {
                    return CustomPaint(
                      painter: CircularBarVisualizer(
                        color: Theme.of(context)
                            .primaryColorLight
                            .withValues(alpha: 0.1),
                        waveData: fft,
                        width: size.width,
                        height: size.height,
                      ),
                      child: const Center(),
                    );
                  },
                  id: 0,
                ),
            ],
          ),
        );
      },
    );
  }
}
