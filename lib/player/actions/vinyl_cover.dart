/// The song's cover as a record sleeve, its record sliding out from behind.
///
/// After the "vinyl slide-out" studies: once the sleeve settles the disc
/// eases out on a spring, a little past half way so its label shows, and
/// while the song
/// plays it turns — slowly, at a record's own pace — so the sheet is alive
/// the way a turntable is, not busy. The label is the cover itself.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion.dart';

class VinylCover extends StatefulWidget {
  const VinylCover({
    super.key,
    required this.cover,
    required this.spinning,
    this.size = 68,
  });

  /// The cover art, drawn square; also used, round, as the record's label.
  final Widget cover;

  /// Whether the record turns (the song is playing).
  final bool spinning;

  /// The sleeve's side.
  final double size;

  /// How far the record comes out, as a share of its width.
  static const peek = 0.56;

  /// How wide the whole thing is at [size] — sleeve plus the record showing.
  static double widthFor(double size) => size + size * 0.94 * peek;

  @override
  State<VinylCover> createState() => _VinylCoverState();
}

class _VinylCoverState extends State<VinylCover> with TickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 820),
  );
  late final Animation<double> _out = CurvedAnimation(
    parent: _slide,
    curve: const SpringCurve(dampingRatio: 0.58),
  );

  /// One turn every 1.8 s: 33⅓ rpm.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  Timer? _start;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_start != null || _slide.value > 0) return;
    if (reduceMotion(context)) {
      _slide.value = 1;
      return;
    }
    // After the panel lands.
    _start = Timer(const Duration(milliseconds: 260), () {
      if (mounted) _slide.forward();
    });
    _syncSpin();
  }

  @override
  void didUpdateWidget(covariant VinylCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spinning != widget.spinning) _syncSpin();
  }

  void _syncSpin() {
    if (widget.spinning && !reduceMotion(context)) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _start?.cancel();
    _slide.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final disc = size * 0.94;
    final travel = disc * VinylCover.peek;
    return SizedBox(
      width: VinylCover.widthFor(size),
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: (size - disc) / 2,
            top: (size - disc) / 2,
            child: _Slide(
              out: _out,
              travel: travel,
              child: RotationTransition(
                turns: _spin,
                child: SizedBox.square(
                  dimension: disc,
                  child: CustomPaint(
                    painter: const _GroovesPainter(),
                    child: Center(
                      child: _Label(cover: widget.cover, size: disc * 0.36),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // The record's sheen stays put while it turns — the light is in
          // the room, not on the record.
          Positioned(
            left: (size - disc) / 2,
            top: (size - disc) / 2,
            child: _Slide(
              out: _out,
              travel: travel,
              child: IgnorePointer(
                child: SizedBox.square(
                  dimension: disc,
                  child: const CustomPaint(painter: _SheenPainter()),
                ),
              ),
            ),
          ),
          // The sleeve, over the record.
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x8C000000),
                  blurRadius: 14,
                  offset: Offset(4, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: widget.cover,
            ),
          ),
        ],
      ),
    );
  }
}

/// Moves [child] right by [travel] as [out] runs.
class _Slide extends AnimatedWidget {
  const _Slide({
    required Animation<double> out,
    required this.travel,
    required this.child,
  }) : super(listenable: out);

  final double travel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final out = listenable as Animation<double>;
    return Transform.translate(
      offset: Offset(travel * out.value, 0),
      child: child,
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.cover, required this.size});

  final Widget cover;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipOval(
            child: SizedBox.square(dimension: size, child: cover),
          ),
          // The spindle hole.
          Container(
            width: size * 0.13,
            height: size * 0.13,
            decoration: const BoxDecoration(
              color: Color(0xFF0B0B0D),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroovesPainter extends CustomPainter {
  const _GroovesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF1C1C20), Color(0xFF09090B)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    var i = 0;
    for (var r = radius * 0.24; r < radius * 0.97; r += 1.6, i++) {
      groove.color = Colors.white.withValues(alpha: i.isEven ? 0.05 : 0.025);
      canvas.drawCircle(center, r, groove);
    }
    // A slightly brighter run-out groove near the label, and the rim.
    canvas.drawCircle(
      center,
      radius * 0.22,
      groove
        ..color = Colors.white.withValues(alpha: 0.12)
        ..strokeWidth = 0.8,
    );
    canvas.drawCircle(
      center,
      radius - 0.5,
      groove
        ..color = Colors.white.withValues(alpha: 0.10)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _GroovesPainter oldDelegate) => false;
}

class _SheenPainter extends CustomPainter {
  const _SheenPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = SweepGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.13),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.09),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.12, 0.24, 0.5, 0.62, 0.74],
          transform: const GradientRotation(-math.pi / 3),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _SheenPainter oldDelegate) => false;
}
