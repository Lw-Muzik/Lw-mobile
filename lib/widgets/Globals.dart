import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import 'artwork_widget.dart';

Widget bottomPlayer(AppController controller, BuildContext context) {
  final song = controller.songs[controller.songId];

  return Container(
    height: 64,
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45)),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        // Artwork thumbnail
        ArtworkWidget(
          songId: song.id,
          path: song.data,
          width: 42,
          height: 42,
          borderRadius: BorderRadius.circular(10),
        ),
        const SizedBox(width: 12),

        // Song info
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.title,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                song.artist ?? 'Unknown artist',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 4),

        // Controls
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ControlButton(
              icon: Icons.skip_previous_rounded,
              onPressed: controller.prev,
              size: 22,
            ),
            StreamBuilder<bool>(
              stream: controller.handler.player.playingStream,
              builder: (context, snapshot) {
                final isPlaying = snapshot.data ?? false;
                return _ControlButton(
                  icon: isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  onPressed: () => isPlaying
                      ? controller.handler.player.pause()
                      : controller.handler.player.play(),
                  size: 28,
                  prominent: true,
                );
              },
            ),
            _ControlButton(
              icon: Icons.skip_next_rounded,
              onPressed: controller.next,
              size: 22,
            ),
          ],
        ),
      ],
    ),
  );
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final bool prominent;

  const _ControlButton({
    required this.icon,
    required this.onPressed,
    this.size = 22,
    this.prominent = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        icon: Icon(
          icon,
          size: size,
          color: prominent ? Colors.white : Colors.white.withValues(alpha: 0.8),
        ),
        splashRadius: 20,
      ),
    );
  }
}
