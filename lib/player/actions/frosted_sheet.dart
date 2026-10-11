/// A floating, frosted panel over the player.
///
/// # Frosted, on purpose
///
/// The app otherwise avoids live blur (see `Ember`): a `BackdropFilter`
/// recomputes every frame. Here it is the design — the player's artwork
/// glows through the panel the way it does through glass — and it is paid
/// only while the sheet is open, over a player whose background is a cached
/// image. Two layers: the player behind softens as the sheet rises, and the
/// panel itself is frosted more heavily.
///
/// The blur behind is driven by the route's own animation, so it eases in with
/// the sheet and clears as the sheet is dragged down, rather than popping.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'motion.dart';

/// Shows [builder]'s content in a frosted panel floating over [context].
Future<T?> showFrostedSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  return navigator.push(
    _FrostedSheetRoute<T>(
      builder: builder,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      isScrollControlled: true,
      useSafeArea: true,
      modalBarrierColor: Colors.black.withValues(alpha: 0.28),
      // A phone's width; on a tablet the panel stays this size, centred.
      constraints: const BoxConstraints(maxWidth: 560),
      sheetAnimationStyle: AnimationStyle(
        duration: const Duration(milliseconds: 560),
        reverseDuration: const Duration(milliseconds: 260),
        curve: const SpringCurve(dampingRatio: 0.74),
        reverseCurve: Curves.easeInCubic,
      ),
    ),
  );
}

class _FrostedSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _FrostedSheetRoute({
    required super.builder,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.backgroundColor,
    super.elevation,
    super.constraints,
    super.modalBarrierColor,
    super.sheetAnimationStyle,
    required super.isScrollControlled,
    super.useSafeArea,
  });

  @override
  Widget buildModalBarrier() {
    final barrier = super.buildModalBarrier();
    final animation = this.animation;
    if (animation == null) return barrier;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = Curves.easeOut.transform(animation.value.clamp(0.0, 1.0));
        if (t < 0.01) return child!;
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14 * t, sigmaY: 14 * t),
          child: child,
        );
      },
      child: barrier,
    );
  }
}

/// The panel: frosted glass with a light edge, floating clear of the screen's
/// edges.
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child});

  final Widget child;

  static const radius = 30.0;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          boxShadow: const [
            BoxShadow(
              color: Color(0x73000000),
              blurRadius: 48,
              offset: Offset(0, 22),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: shape,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: shape,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xB8212127), Color(0xD9101013)],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              ),
              child: Stack(
                children: [
                  // The specular edge: light catching the panel's top rim.
                  Positioned(
                    left: 24,
                    right: 24,
                    top: 0,
                    height: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.32),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The grab handle at the panel's top.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        width: 38,
        height: 5,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}
