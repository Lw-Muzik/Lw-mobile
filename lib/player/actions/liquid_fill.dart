/// A download filling its button like liquid.
///
/// After the "download button" studies: the level rises with the download,
/// its surface a gentle double wave that never quite stills while it works,
/// and settles flat once full. The level glides to each new value rather
/// than stepping, because progress arrives in uneven jumps.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion.dart';

class LiquidFill extends StatefulWidget {
  const LiquidFill({
    super.key,
    required this.level,
    required this.color,
    required this.child,
  });

  /// 0–1, or null while the download's size is unknown — then a shallow
  /// tide, so it still reads as working.
  final double? level;
  final Color color;
  final Widget child;

  @override
  State<LiquidFill> createState() => _LiquidFillState();
}

class _LiquidFillState extends State<LiquidFill> with TickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  late final AnimationController _level = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: _target,
  );
  late Animation<double> _levelTween = AlwaysStoppedAnimation(_target);

  double get _target => widget.level ?? 0.12;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context) && !_wave.isAnimating) _wave.repeat();
  }

  @override
  void didUpdateWidget(covariant LiquidFill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level) {
      final from = _levelTween.value;
      _levelTween = Tween(
        begin: from,
        end: _target,
      ).animate(CurvedAnimation(parent: _level, curve: Curves.easeOutCubic));
      _level.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    _level.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LiquidPainter(
        wave: _wave,
        level: _levelTween,
        color: widget.color,
        repaint: Listenable.merge([_wave, _level]),
      ),
      child: widget.child,
    );
  }
}

class _LiquidPainter extends CustomPainter {
  _LiquidPainter({
    required this.wave,
    required this.level,
    required this.color,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Animation<double> wave;
  final Animation<double> level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = level.value.clamp(0.0, 1.0);
    if (fill <= 0) return;
    final phase = wave.value * 2 * math.pi;
    // Calm at the bottom and the top: a full button is still water.
    final amplitude = 3.2 * math.sin(math.pi * fill).clamp(0.25, 1.0);
    final surface = size.height * (1 - fill);

    Path waveAt(double shift, double scale) {
      final path = Path()..moveTo(0, size.height);
      for (double x = 0; x <= size.width; x += 2) {
        final y =
            surface +
            math.sin(x / size.width * 2 * math.pi * 1.2 + phase + shift) *
                amplitude *
                scale;
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      return path;
    }

    canvas.drawPath(
      waveAt(math.pi * 0.8, 0.8),
      Paint()..color = color.withValues(alpha: color.a * 0.45),
    );
    canvas.drawPath(waveAt(0, 1), Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _LiquidPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.level != level ||
      oldDelegate.wave != wave;
}
