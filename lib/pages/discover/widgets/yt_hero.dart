/// The pieces the album and artist pages' headers are built from — the pages
/// the player's "Go to album" and "Go to artist" open.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../player/actions/motion.dart';
import '../../../themes/ember.dart';

/// A round button over artwork: frosted [icon], or for the one main action a
/// solid gold disc with a dark icon ([primary]) — gold carries dark content
/// (see `Ember.accent`).
class YtRoundButton extends StatefulWidget {
  const YtRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 48,
    this.primary = false,
    this.child,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;
  final bool primary;

  /// Drawn instead of the icon (a progress ring).
  final Widget? child;

  @override
  State<YtRoundButton> createState() => _YtRoundButtonState();
}

class _YtRoundButtonState extends State<YtRoundButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.9 : 1,
          duration: const Duration(milliseconds: 140),
          curve: _down ? Curves.easeOut : const SpringCurve(dampingRatio: 0.5),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.primary
                  ? Ember.accent
                  : Colors.white.withValues(alpha: 0.1),
              border: widget.primary
                  ? null
                  : Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: widget.primary
                  ? [
                      BoxShadow(
                        color: Ember.accent.withValues(alpha: 0.35),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child:
                  widget.child ??
                  Icon(
                    widget.icon,
                    size: widget.size * (widget.primary ? 0.52 : 0.44),
                    color: widget.primary
                        ? Ember.ground
                        : Colors.white.withValues(alpha: enabled ? 0.92 : 0.35),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three bars rising and falling: this one is playing.
class NowPlayingBars extends StatefulWidget {
  const NowPlayingBars({super.key, this.playing = true, this.size = 16});

  final bool playing;
  final double size;

  @override
  State<NowPlayingBars> createState() => _NowPlayingBarsState();
}

class _NowPlayingBarsState extends State<NowPlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant NowPlayingBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.playing && !reduceMotion(context)) {
      if (!_beat.isAnimating) _beat.repeat();
    } else {
      _beat.stop();
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(painter: _BarsPainter(_beat)),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.beat) : super(repaint: beat);

  final Animation<double> beat;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Ember.accent
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width / 5;
    const phases = [0.0, 0.33, 0.66];
    for (var i = 0; i < 3; i++) {
      final t = (beat.value + phases[i]) % 1;
      // A rise and fall per cycle, never quite flat.
      final level = 0.3 + 0.7 * (0.5 - 0.5 * math.cos(t * 2 * math.pi));
      final x = size.width * (0.2 + i * 0.3);
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height * (1 - level)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter oldDelegate) => false;
}
