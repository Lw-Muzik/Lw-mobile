/// The picture itself.
///
/// A thin widget over the platform texture: it claims the surface for as long as
/// it is mounted, draws the frames at the shape the decoder reports, and gets out
/// of the way. Controls, gestures and quality live in their own files — this one
/// is only responsible for showing what is playing.
library;

import 'package:flutter/material.dart';
import 'package:just_audio/video.dart';

import '../../controllers/AppController.dart';
import 'video_surface.dart';

class VideoStage extends StatefulWidget {
  /// Which of the three places this instance is.
  final VideoHost host;

  /// How the frames fill the space they are given.
  ///
  /// [BoxFit.contain] everywhere by default: a music video's framing is part of
  /// the work, and cropping it to fill a card is a decision the app should not
  /// make on the viewer's behalf. Full screen offers the alternative as a
  /// gesture.
  final BoxFit fit;

  /// Drawn while the first frame is still on its way.
  final Widget? placeholder;

  const VideoStage({
    super.key,
    required this.host,
    this.fit = BoxFit.contain,
    this.placeholder,
  });

  @override
  State<VideoStage> createState() => _VideoStageState();
}

class _VideoStageState extends State<VideoStage> {
  VideoOutput get _video => AppController.instance.handler.video;

  @override
  void initState() {
    super.initState();
    VideoSurface.instance.claim(widget.host);
  }

  @override
  void dispose() {
    VideoSurface.instance.release(widget.host);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: VideoSurface.instance,
      builder: (context, _) {
        // Mounted but outranked — full screen is open above this card. Drawing
        // the same texture in both places would be two views of one stream
        // competing for it; the one nobody is looking at yields.
        if (!VideoSurface.instance.isOwner(widget.host)) {
          return widget.placeholder ?? const SizedBox.shrink();
        }
        return ValueListenableBuilder<int?>(
          valueListenable: _video.texture,
          builder: (context, textureId, _) {
            if (textureId == null) {
              return widget.placeholder ?? const _VideoPlaceholder();
            }
            return StreamBuilder<VideoState>(
              stream: _video.stateStream,
              initialData: _video.state,
              builder: (context, snapshot) {
                final state = snapshot.data ?? const VideoState();
                return ColoredBox(
                  color: Colors.black,
                  child: FittedBox(
                    fit: widget.fit,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      // The decoder's own dimensions, scaled by the box above.
                      // Laying out at the true size and letting `FittedBox` do
                      // the arithmetic keeps aspect handling in one place.
                      width: state.hasVideo ? state.width.toDouble() : 1600,
                      height: state.hasVideo ? state.height.toDouble() : 900,
                      child: Texture(textureId: textureId),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// A block the shape of a video rather than a spinner — the same loading
/// language the rest of Discover uses.
class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
