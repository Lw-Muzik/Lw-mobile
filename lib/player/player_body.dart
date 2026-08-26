import 'dart:ui';

import '/exports/exports.dart';
import '../controllers/app_controller.dart';
import '../widgets/artwork_widget.dart';

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
        // The native tap is no longer poked from here. It used to be started by
        // a platform call made *inside build*, which fired on every controller
        // notify — play-count, EQ drag, track change. AppController now owns the
        // tap and only calls across when it actually has to start or stop.
        final size = MediaQuery.of(context).size;
        final song = controller.songs[controller.songId];

        return Stack(
          children: [
            // Background artwork, blurred, with a smooth crossfade on track
            // change. Isolated so the player UI animating above it — controls,
            // seek bar, card deck — cannot drag the blur into a repaint.
            RepaintBoundary(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                child: SizedBox(
                  key: ValueKey(song.id),
                  height: size.height,
                  width: size.width,
                  child: ImageFiltered(
                    // See Body._BodyBackground: this blurs the cover, and the
                    // cover is the only thing under it. A backdrop filter reads
                    // the surface it lands on and so re-blurred the whole screen
                    // every frame; filtering the child caches with the artwork.
                    imageFilter: ImageFilter.blur(
                      sigmaX: controller.blur + 10,
                      sigmaY: controller.blur + 10,
                      tileMode: TileMode.clamp,
                    ),
                    child: ArtworkWidget(
                      height: size.height,
                      width: size.width,
                      songId: song.id,
                      size: 2000,
                      type: ArtworkType.AUDIO,
                      path: song.data,
                    ),
                  ),
                ),
              ),
            ),
            // Dark gradient overlay
            Container(
              height: size.height,
              width: size.width,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.40),
                    Colors.black.withValues(alpha: 0.60),
                    Colors.black.withValues(alpha: 0.85),
                    Colors.black.withValues(alpha: 0.95),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.3, 0.7, 1.0],
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
