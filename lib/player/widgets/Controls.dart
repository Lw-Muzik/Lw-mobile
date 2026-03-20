import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../controllers/AppController.dart';
import '../../Helpers/AudioHandler.dart';

class Controls extends StatelessWidget {
  final VoidCallback? onNextPressed;
  final VoidCallback? onPrevPressed;

  const Controls({super.key, this.onNextPressed, this.onPrevPressed});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ShuffleButton(controller: controller),
              const SizedBox(width: 12),
              _SkipButton(
                icon: Icons.skip_previous_rounded,
                onPressed: () {
                  // Animate first, then skip (prev callback triggers controller.prev)
                  onPrevPressed?.call();
                },
              ),
              const SizedBox(width: 16),
              _PlayPauseButton(controller: controller),
              const SizedBox(width: 16),
              _SkipButton(
                icon: Icons.skip_next_rounded,
                onPressed: () {
                  // Animate first, then skip (next callback triggers controller.next)
                  onNextPressed?.call();
                },
              ),
              const SizedBox(width: 12),
              _RepeatButton(controller: controller),
            ],
          ),
        );
      },
    );
  }
}

/// Large circular play/pause button.
class _PlayPauseButton extends StatelessWidget {
  final AppController controller;
  const _PlayPauseButton({required this.controller});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: controller.handler.player.playerStateStream,
      builder: (context, snapshot) {
        final playerState = snapshot.data;
        final processingState = playerState?.processingState;
        final playing = playerState?.playing ?? false;

        if (processingState == ProcessingState.loading ||
            processingState == ProcessingState.buffering) {
          return Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 2),
            ),
            child: const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
            ),
          );
        }

        final icon = processingState == ProcessingState.completed
            ? Icons.replay_rounded
            : playing
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded;

        final onPressed = processingState == ProcessingState.completed
            ? () => controller.handler.player.seek(Duration.zero)
            : playing
                ? controller.handler.player.pause
                : controller.handler.player.play;

        return GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.12),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, size: 38, color: const Color(0xFF0B1220)),
          ),
        );
      },
    );
  }
}

/// Skip previous / next — 48dp minimum tap target.
class _SkipButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  const _SkipButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 36),
        ),
      ),
    );
  }
}

/// Shuffle toggle — uses app-level shuffle (not just_audio's internal mode).
class _ShuffleButton extends StatelessWidget {
  final AppController controller;
  const _ShuffleButton({required this.controller});

  static const _accent = Color(0xFFD4A825);

  @override
  Widget build(BuildContext context) {
    final enabled = controller.isShuffled;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (enabled) {
            controller.isShuffled = false;
            controller.unshuffleSongs();
          } else {
            controller.isShuffled = true;
            controller.shuffleSongs();
          }
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: enabled
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accent.withValues(alpha: 0.15),
                )
              : null,
          child: Icon(
            Icons.shuffle_rounded,
            color: enabled ? _accent : Colors.white38,
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// Repeat / loop mode toggle — 48dp tap target with visible active state.
class _RepeatButton extends StatelessWidget {
  final AppController controller;
  const _RepeatButton({required this.controller});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LoopMode>(
      stream: controller.handler.player.loopModeStream,
      builder: (context, snapshot) {
        final mode = snapshot.data ?? LoopMode.off;
        final IconData icon;
        final Color color;
        final bool active;

        switch (mode) {
          case LoopMode.off:
            icon = Icons.repeat_rounded;
            color = Colors.white38;
            active = false;
          case LoopMode.all:
            icon = Icons.repeat_rounded;
            color = const Color(0xFFD4A825);
            active = true;
          case LoopMode.one:
            icon = Icons.repeat_one_rounded;
            color = const Color(0xFFD4A825);
            active = true;
        }

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              const modes = [LoopMode.off, LoopMode.all, LoopMode.one];
              final next = modes[(modes.indexOf(mode) + 1) % modes.length];
              controller.handler.player.setLoopMode(next);
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: active
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFD4A825).withValues(alpha: 0.15),
                    )
                  : null,
              child: Icon(icon, color: color, size: 22),
            ),
          ),
        );
      },
    );
  }
}
