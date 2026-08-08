/// The video that follows you around the app.
///
/// # Why this exists
///
/// Leaving the player screen should not end the video any more than it ends the
/// song. The audio never stops — it is the same player inside the same
/// background service — but the picture has nowhere to be drawn once the player
/// screen is gone. This gives it somewhere: a small window over whatever the
/// user browses to next, draggable out of the way and dismissible.
///
/// # It appears only when it is the only place left
///
/// Mounted for the whole life of the app, but it shows itself only when the
/// current track is a video *and* neither the player card nor the full-screen
/// route is already showing it. A floating copy of a video playing full size
/// behind it would be clutter, and two views of one texture would be two hosts
/// competing for it.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../Routes/routes.dart';
import '../../controllers/AppController.dart';
import '../../services/video/video_registry.dart';
import 'video_stage.dart';
import 'video_surface.dart';

class VideoMiniPlayer extends StatefulWidget {
  const VideoMiniPlayer({super.key});

  @override
  State<VideoMiniPlayer> createState() => _VideoMiniPlayerState();
}

class _VideoMiniPlayerState extends State<VideoMiniPlayer> {
  static const _width = 190.0;
  static const _margin = 12.0;

  /// Where the user last put it, or null for the default corner.
  Offset? _position;

  /// Set when the user dismisses it, cleared when a different video starts —
  /// closing this window means "not this one", not "never again".
  int? _dismissedSongId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: VideoSurface.instance,
      builder: (context, _) => Consumer<AppController>(
        builder: (context, controller, _) {
          final song = controller.songs.isEmpty
              ? null
              : controller.songs[
                  controller.songId.clamp(0, controller.songs.length - 1)];
          final isVideo =
              song != null && VideoRegistry.instance.isVideo(song.id);

          if (_dismissedSongId != null && _dismissedSongId != song?.id) {
            _dismissedSongId = null;
          }
          final hidden = !isVideo ||
              _dismissedSongId == song.id ||
              VideoSurface.instance.claimedByOther(VideoHost.mini);
          if (hidden) return const SizedBox.shrink();

          final media = MediaQuery.of(context);
          final height = _width * 9 / 16;
          final defaultPosition = Offset(
            media.size.width - _width - _margin,
            media.size.height - height - media.padding.bottom - 92,
          );
          final position = _position ?? defaultPosition;

          return Positioned(
            left: position.dx.clamp(0.0, media.size.width - _width),
            top: position.dy.clamp(
              media.padding.top,
              media.size.height - height - media.padding.bottom,
            ),
            child: _MiniWindow(
              width: _width,
              height: height,
              title: song.title,
              onDrag: (delta) => setState(() {
                _position = (_position ?? defaultPosition) + delta;
              }),
              onTap: () => Routes.playerTo(context),
              onClose: () => setState(() => _dismissedSongId = song.id),
            ),
          );
        },
      ),
    );
  }
}

class _MiniWindow extends StatelessWidget {
  final double width;
  final double height;
  final String title;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _MiniWindow({
    required this.width,
    required this.height,
    required this.title,
    required this.onDrag,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) => onDrag(details.delta),
      onTap: onTap,
      child: Material(
        elevation: 10,
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const VideoStage(host: VideoHost.mini),
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  onTap: onClose,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(10),
                      ),
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 16),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 5),
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
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
