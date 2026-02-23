import 'dart:ui';

import '/exports/exports.dart';
import '../Helpers/AudioVisualizer.dart';
import '../controllers/AppController.dart';
import '../widgets/ArtworkWidget.dart';

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
        if (controller.visuals) {
          Visualizers.enableVisual(true);
        }
        final size = MediaQuery.of(context).size;
        final song = controller.songs[controller.songId];

        return Stack(
          children: [
            // Background artwork with smooth crossfade on track change.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              child: SizedBox(
                key: ValueKey(song.id),
                height: size.height,
                width: size.width,
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
            // Heavy blur + dark gradient overlay
            BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: controller.blur + 10,
                sigmaY: controller.blur + 10,
              ),
              child: Container(
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
            ),
            widget.child,
          ],
        );
      },
    );
  }
}
