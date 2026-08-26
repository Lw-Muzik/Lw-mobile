/// The arithmetic behind the player's card deck.
///
/// Kept apart from the widget because all three rules below used to be spread
/// across a gesture handler, a `didUpdateWidget`, three `AnimationController`s
/// and a pair of boolean flags — and every one of their failures is silent.
/// A deck that reconciles wrong shows the wrong art; a deck whose geometry is
/// discontinuous "snaps" at the end of a swipe. Neither throws.
library;

/// How the deck must move to catch up with the track that is actually playing.
enum DeckStep {
  /// Already showing it.
  none,

  /// One track forward: throw the front card away.
  next,

  /// One track back: bring the previous card home.
  previous,
}

/// What the deck must do to show [target] when it is currently showing [shown].
///
/// This is the whole of the reactive rule. The deck does not care *why* the
/// index moved — a swipe, the track ending, a crossfade starting, a headphone
/// button, the notification — which is exactly why no source of change can be
/// forgotten. Every one of them lands here.
///
/// [itemCount] is only needed to recognise a wrap. Under repeat-all the last
/// track's "next" sets the index to 0, which by arithmetic alone looks like a
/// forty-track jump; to the person who pressed the button it is one track
/// forward and has to look like it.
/// # Every move is a card move
///
/// A jump of forty tracks used to cross-fade instead of throwing, on the
/// reasoning that no card metaphor fits travelling that far. In practice a
/// cross-fade of two album covers does not read as distance — it reads as a
/// flicker, two pictures briefly superimposed, which is the one thing a deck
/// of cards should never do.
///
/// So distance decides *where* the deck lands and never *how* it moves. A jump
/// throws one card and brings the destination in behind it, which is what
/// moving a card by hand looks like however far you reached. `_trackAt` already
/// draws the arriving card from the destination rather than from
/// `_index ± 1`, so the card that lands is the right one.
DeckStep reconcile({
  required int shown,
  required int target,
  int? itemCount,
}) {
  final delta = target - shown;
  if (delta == 0) return DeckStep.none;

  if (itemCount != null && itemCount > 2) {
    // A repeat-all wrap is one track forward to someone pressing the button,
    // even though the arithmetic says it is the length of the queue backwards.
    final last = itemCount - 1;
    if (shown == last && target == 0) return DeckStep.next;
    if (shown == 0 && target == last) return DeckStep.previous;
  }

  return delta > 0 ? DeckStep.next : DeckStep.previous;
}

/// What a released drag means.
enum DragOutcome { next, previous, snapBack }

/// Reads a released drag as an intention.
///
/// Distance OR speed commits, so both a deliberate push and a quick flick work;
/// speed wins when they disagree, because a fast flick that has not travelled
/// far is still unambiguously a throw.
DragOutcome resolveDrag({
  required double dx,
  required double velocity,
  required double width,
  required bool canNext,
  required bool canPrevious,
  double distanceFraction = 0.15,
  double flingVelocity = 600.0,
}) {
  final isFling = velocity.abs() > flingVelocity;
  final isFar = dx.abs() > width * distanceFraction;
  if (!isFling && !isFar) return DragOutcome.snapBack;

  // A flick's direction is its velocity, not where the finger happens to have
  // ended up: flick-and-return is a flick.
  final forward = isFling ? velocity > 0 : dx > 0;
  if (forward) return canNext ? DragOutcome.next : DragOutcome.snapBack;
  return canPrevious ? DragOutcome.previous : DragOutcome.snapBack;
}

/// Where a card sits in the stack.
class CardLayout {
  final double scale;
  final double dy;
  final double opacity;

  const CardLayout({
    required this.scale,
    required this.dy,
    required this.opacity,
  });
}

/// Geometry of a card at a *continuous* depth.
///
/// Depth is not an integer. A card at depth 2 sliding into the depth-1 slot
/// passes through 1.7, 1.4, 1.1 … and this is the only place that shape is
/// defined. Because every term is linear in [depth], the deck at the instant a
/// transition completes (every card at depth d − 1) is pixel-identical to the
/// deck once the index has committed and the same card is genuinely at depth
/// d − 1. That identity IS the absence of a snap — see the test that asserts
/// it. Anything non-linear here, or any second timeline running alongside this
/// one, puts the jump back.
CardLayout layoutAt(
  double depth, {
  double scaleFraction = 0.05,
  double yOffset = 12.0,
  double opacityFalloff = 0.12,
}) {
  return CardLayout(
    scale: 1.0 - depth * scaleFraction,
    dy: -depth * yOffset,
    opacity: (1.0 - depth * opacityFalloff).clamp(0.0, 1.0),
  );
}

/// Signed movement the stack makes while a step is [progress] through it.
///
/// Going forward, every card rises one slot, so depth *decreases*. Going back
/// they sink. Adding this to a card's resting depth gives the depth to draw it
/// at, and the incoming previous card rests at −1 so it arrives at 0 exactly
/// when the step finishes.
double stackShift(DeckStep step, double progress) => switch (step) {
      DeckStep.next => -progress,
      DeckStep.previous => progress,
      DeckStep.none => 0.0,
    };
