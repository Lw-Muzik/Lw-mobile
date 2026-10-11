/// The motion vocabulary of the song actions sheet.
///
/// Taken from the glass-morph studies it was designed from: the panel lands
/// on a spring rather than an ease, rows arrive one after another instead of
/// all at once, and moving between the sheet's pages reshapes the one panel —
/// it does not stack a second sheet — with the outgoing page blurring away
/// as the next sharpens in.
///
/// Everything here stands still when the system asks for reduced motion.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// A damped spring settling on 1: one soft overshoot, then rest.
///
/// [dampingRatio] sets the overshoot — 0.7 lands about 5 % past and back,
/// lower is bouncier. The spring's own settling time is stretched over the
/// animation's duration, so the duration chooses the speed and this only the
/// shape.
class SpringCurve extends Curve {
  const SpringCurve({this.dampingRatio = 0.7});

  final double dampingRatio;

  @override
  double transformInternal(double t) {
    const omega = 14.0;
    final zeta = dampingRatio.clamp(0.05, 0.99);
    // Time for the envelope to fall to 1 %, so t = 1 is at rest.
    final settle = 4.6 / (zeta * omega);
    final time = t * settle;
    final damped = omega * math.sqrt(1 - zeta * zeta);
    final envelope = math.exp(-zeta * omega * time);
    return 1 -
        envelope *
            (math.cos(damped * time) +
                (zeta * omega / damped) * math.sin(damped * time));
  }
}

/// Whether the system asked for reduced motion.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// One row arriving in its turn: risen a little and faded in, [index] steps
/// after the first.
class Cascade extends StatefulWidget {
  const Cascade({
    super.key,
    required this.index,
    required this.child,
    this.step = const Duration(milliseconds: 38),
    this.delay = const Duration(milliseconds: 90),
  });

  final int index;
  final Widget child;

  /// Between one row and the next.
  final Duration step;

  /// Before the first, so the panel has landed before its rows do.
  final Duration delay;

  @override
  State<Cascade> createState() => _CascadeState();
}

class _CascadeState extends State<Cascade> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  Timer? _start;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.value > 0 || _start != null) {
      return;
    }
    if (reduceMotion(context)) {
      _controller.value = 1;
      return;
    }
    _start = Timer(widget.delay + widget.step * widget.index, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _start?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final t = _curve.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 14),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Swaps the sheet's pages by reshaping one panel around them.
///
/// The panel's height springs to the new page's — a small overshoot, then
/// rest — while the old page slides out and blurs away and the new one slides
/// in from the side it was asked from and sharpens. [forward] is which way:
/// deeper into the sheet comes in from the right, back from the left.
class PageMorph extends StatelessWidget {
  const PageMorph({
    super.key,
    required this.pageKey,
    required this.forward,
    required this.child,
  });

  /// Identifies the page showing; a new key is a new page.
  final Object pageKey;
  final bool forward;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return AnimatedSize(
      duration: Duration(milliseconds: still ? 0 : 520),
      curve: const SpringCurve(dampingRatio: 0.66),
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: still ? 0 : 340),
        reverseDuration: Duration(milliseconds: still ? 0 : 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        // Only the incoming page sizes the panel; the outgoing one is laid
        // over it while it leaves, so the height moves once, not twice.
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [
            for (final page in previous)
              Positioned(left: 0, right: 0, top: 0, child: page),
            ?current,
          ],
        ),
        transitionBuilder: (child, animation) {
          final incoming = child.key == ValueKey(pageKey);
          // Incoming pages arrive from the direction of travel; outgoing ones
          // leave toward the other side.
          final from = (incoming == forward) ? 0.18 : -0.18;
          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final t = animation.value;
              final blur = (1 - t) * 8;
              return FractionalTranslation(
                translation: Offset(from * (1 - t), 0),
                child: Opacity(
                  opacity: t,
                  child: blur < 0.05
                      ? child
                      : ImageFiltered(
                          imageFilter: ImageFilter.blur(
                            sigmaX: blur,
                            sigmaY: blur,
                          ),
                          child: child,
                        ),
                ),
              );
            },
            child: child,
          );
        },
        child: KeyedSubtree(key: ValueKey(pageKey), child: child),
      ),
    );
  }
}
