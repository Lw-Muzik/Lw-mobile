import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import 'deck_motion.dart';

export 'deck_motion.dart';

// ─── Configuration ──────────────────────────────────────────────────────────

class CardAnimationConfig {
  static const int maxVisibleCards = 4;
  static const double scaleFraction = 0.05;
  static const double yOffset = 12.0;

  /// Fraction of screen width that commits a swipe on distance alone.
  static const double swipeThreshold = 0.15;

  /// Speed (px/s) that commits a swipe regardless of distance.
  static const double flingVelocity = 600.0;

  /// How far a card travels to leave, as a multiple of screen width. Also the
  /// distance an incoming card comes from, so the two directions are mirror
  /// images of each other rather than two separately-tuned effects.
  static const double travelFraction = 1.15;

  /// Rotation at full travel (degrees).
  static const double throwRotationDeg = 18.0;

  /// How much the front card slides with a backward drag. It is being covered,
  /// not thrown, so it barely moves — but it moves, because a card that
  /// ignores your finger entirely reads as a dead surface.
  static const double backwardFollow = 0.25;

  /// Resistance when there is nothing to move to. The card gives a little and
  /// pulls back, which says "end of the queue" without a message.
  static const double rubberBand = 0.3;

  /// Lift as a card leaves, in logical pixels at full travel.
  static const double throwLift = 34.0;

  /// A programmatic move is a hand throw the user did not make. Expressed in
  /// travels-per-second, so it takes the same time on any screen.
  static const double syntheticVelocity = 2.3;


  /// Carries a thrown card off the screen. Critically damped: a card that
  /// bounces on its way out is a spring, not a card.
  static final SpringDescription throwSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 190, ratio: 1.0);

  /// Returns an uncommitted card to the deck. Slightly underdamped so it
  /// arrives with a small settle instead of stopping dead.
  static final SpringDescription settleSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 380, ratio: 0.86);
}

// ─── Animated Player Card Widget ────────────────────────────────────────────

/// A deck of cards that follows whatever track is actually playing.
///
/// # Why this follows rather than being driven
///
/// The index it shows can move for at least six reasons: a swipe, the next or
/// previous button, a track ending under gapless playback, a track ending
/// without it, a crossfade starting seconds before the track ends, and the
/// notification or a headphone button. The deck used to have a separate trigger
/// for some of these and nothing at all for the rest, which is why crossfades
/// and the previous button teleported — nobody had wired them up, and there was
/// no place where forgetting one would be noticed.
///
/// So the deck subscribes to the outcome instead of the causes: it watches
/// `currentSongId` and animates toward it. A swipe is not special — it changes
/// the track like everything else and the deck reacts the same way. Adding a
/// seventh source of change requires no work here.
///
/// # Why one number
///
/// All motion is a single signed value [_s]: `+1` is one track forward, `-1`
/// one back, `0` at rest. Card offsets, stack depths, rotation, opacity and
/// lift are all read off it. The previous implementation ran three
/// `AnimationController`s of 380 ms, 350 ms and 250 ms against each other, so
/// the stack stopped rising at a different instant than the thrown card
/// committed and the difference was visible as a snap. With one value there is
/// no second timeline to disagree with.
class AnimatedPlayerCard extends StatefulWidget {
  final int itemCount;
  final int currentSongId;

  /// Called when the *user* moved the deck, never when the deck is catching up
  /// with a change someone else made. Fires the moment the gesture commits, so
  /// the audio responds to the flick rather than to the end of the animation.
  final Function(int) onPageChanged;

  final Widget Function(BuildContext, int, {bool isActive}) itemBuilder;

  const AnimatedPlayerCard({
    super.key,
    required this.itemCount,
    required this.currentSongId,
    required this.onPageChanged,
    required this.itemBuilder,
  });

  @override
  AnimatedPlayerCardState createState() => AnimatedPlayerCardState();
}

class AnimatedPlayerCardState extends State<AnimatedPlayerCard>
    with TickerProviderStateMixin {
  /// Signed progress of the move in flight. See the class comment.
  late final AnimationController _motion;

  /// The track whose card is currently the front of the deck.
  int _index = 0;

  /// Where the deck is going, while it is going there. Distinct from [_index]
  /// so the audio can change at the moment a gesture commits while the card is
  /// still flying — and so a `currentSongId` that arrives mid-flight is
  /// recognised as the move already under way rather than a new one.
  int? _pending;

  bool _dragging = false;
  double _rawDrag = 0;

  /// Where the finger landed, as a [Transform] alignment. A real card pivots
  /// about the point you are holding, so one grabbed near a corner swings more
  /// than one held in the middle.
  Alignment _pivot = Alignment.center;

  double get _s => _motion.value;

  double _travel = 400 * CardAnimationConfig.travelFraction;

  @override
  void initState() {
    super.initState();
    _index = widget.currentSongId;
    _motion = AnimationController.unbounded(vsync: this)
      ..addListener(_onMotionTick);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  // ── Reconciliation ──

  /// Where the deck will be once everything in flight has landed.
  int get _destination => _pending ?? _index;

  @override
  void didUpdateWidget(AnimatedPlayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.itemCount == 0) return;
    if (_index >= widget.itemCount) {
      setState(() => _index = widget.itemCount - 1);
    }
    // Mid-gesture the finger is the authority. Whatever arrived is reconciled
    // on release, by which time it may no longer be a difference at all.
    if (_dragging) return;

    _reconcile();
  }

  void _reconcile() {
    final target = widget.currentSongId.clamp(0, widget.itemCount - 1);
    switch (reconcile(
      shown: _destination,
      target: target,
      itemCount: widget.itemCount,
    )) {
      case DeckStep.none:
        return;
      case DeckStep.next:
        _launch(DeckStep.next, CardAnimationConfig.syntheticVelocity, target);
      case DeckStep.previous:
        _launch(
            DeckStep.previous, -CardAnimationConfig.syntheticVelocity, target);
    }
  }

  /// Springs the deck one card in [step], seeded with [velocity] in travels/s,
  /// landing on [destination].
  ///
  /// Seeding rather than replaying a fixed curve is what makes a hard flick
  /// leave faster than a gentle push: same code, different initial conditions.
  /// Programmatic moves supply a synthetic velocity and so are indistinguishable
  /// from a moderate hand throw.
  ///
  /// [destination] is passed rather than derived because a repeat-all wrap is
  /// one card's worth of movement to somewhere that is not one index away.
  void _launch(DeckStep step, double velocity, int destination) {
    _pending = destination;

    // Aim past the commit point so the card is still moving when it gets
    // there. Springing exactly to 1 would crawl the last few percent.
    final target = step == DeckStep.next ? 1.06 : -1.06;
    _motion.animateWith(
      SpringSimulation(
        CardAnimationConfig.throwSpring,
        _s,
        target,
        velocity,
      ),
    );
  }

  void _onMotionTick() {
    if (!mounted) return;
    // Commit as soon as the card has covered a whole travel. The geometry at
    // that instant is identical to the committed deck's — see the continuity
    // test in deck_motion_test.dart — so resetting to zero here is invisible.
    if (_pending != null && _s.abs() >= 1.0) {
      _motion.stop();
      final landed = _pending!;
      _pending = null;
      _motion.value = 0;
      setState(() => _index = landed.clamp(0, widget.itemCount - 1));
      // Something may have moved again while this card was in the air.
      _reconcile();
      return;
    }
    setState(() {});
  }

  // ── Gestures ──

  bool get _canNext => _destination < widget.itemCount - 1;
  bool get _canPrevious => _destination > 0;

  void _onDragStart(DragStartDetails details, Size size) {
    if (_pending != null) return;
    _dragging = true;
    _rawDrag = 0;
    _motion.stop();
    // Alignment is -1..1 across the box, so a touch at the left edge is -1.
    _pivot = Alignment(
      (details.localPosition.dx / size.width) * 2 - 1,
      (details.localPosition.dy / size.height) * 2 - 1,
    );
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    _rawDrag += details.delta.dx;

    // Past the end of the queue the card resists instead of moving freely.
    final blocked = (_rawDrag > 0 && !_canNext) || (_rawDrag < 0 && !_canPrevious);
    final effective =
        blocked ? _rawDrag * CardAnimationConfig.rubberBand : _rawDrag;

    _motion.value = (effective / _travel).clamp(-1.0, 1.0);
    setState(() {});
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;

    final vx = details.velocity.pixelsPerSecond.dx;
    final outcome = resolveDrag(
      dx: _rawDrag,
      velocity: vx,
      width: _travel / CardAnimationConfig.travelFraction,
      canNext: _canNext,
      canPrevious: _canPrevious,
      distanceFraction: CardAnimationConfig.swipeThreshold,
      flingVelocity: CardAnimationConfig.flingVelocity,
    );

    // Hand the gesture's own speed to the spring, in the units it works in.
    final velocity = vx / _travel;

    switch (outcome) {
      case DragOutcome.next:
        _commitUserMove(DeckStep.next, velocity);
      case DragOutcome.previous:
        _commitUserMove(DeckStep.previous, velocity);
      case DragOutcome.snapBack:
        _motion.animateWith(
          SpringSimulation(
            CardAnimationConfig.settleSpring,
            _s,
            0,
            velocity,
          ),
        );
    }
  }

  /// The user committed a swipe: tell the audio now, animate the rest.
  ///
  /// Changing the track here rather than when the card lands is what makes a
  /// flick feel answered. The resulting `currentSongId` matches [_pending], so
  /// [_reconcile] sees the move already in flight and does not start a second.
  void _commitUserMove(DeckStep step, double velocity) {
    // A swipe never wraps — [_canNext] and [_canPrevious] stop it at the ends
    // of the queue — so the destination is always the neighbour.
    final destination = _index + (step == DeckStep.next ? 1 : -1);
    _launch(step, velocity, destination);
    widget.onPageChanged(destination);
  }

  // ── Painting ──

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        _travel = size.width * CardAnimationConfig.travelFraction;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          // Horizontal, not pan: the player's vertical drag dismisses the
          // screen, and two pan recognisers in one arena made a diagonal
          // gesture's outcome a coin toss. Declaring an axis lets the arena
          // resolve it the way the user meant.
          onHorizontalDragStart: (d) => _onDragStart(d, size),
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          child: Stack(fit: StackFit.expand, children: _buildCards()),
        );
      },
    );
  }

  /// Which track belongs in the slot [depth] cards back, or null for a slot
  /// past the end of the queue.
  ///
  /// The card arriving during a step is the *destination*, which is not always
  /// the neighbour: a repeat-all wrap is one card's worth of movement from the
  /// last track to the first. Reading `_index + depth` there would leave the
  /// slot empty and the thrown card would fly off over nothing.
  int? _trackAt(int depth) {
    if (_pending case final destination?) {
      if (depth == 1 && _s > 0) return destination;
      if (depth == -1 && _s < 0) return destination;
    }
    final index = _index + depth;
    if (index < 0 || index >= widget.itemCount) return null;
    return index;
  }

  List<Widget> _buildCards() {
    final step = _s > 0
        ? DeckStep.next
        : _s < 0
            ? DeckStep.previous
            : DeckStep.none;
    final shift = stackShift(step, _s.abs());

    // A backward move needs the card above the deck — the one being brought
    // home. It rests at -1 so it arrives at the front slot exactly on commit.
    final shallowest = _s < 0 ? -1 : 0;

    // While the route is still opening or closing, the front card is a Hero and
    // Hero *hides* its child in flight, leaving an empty box the size of the
    // card. Whatever the deck draws behind it is then fully visible — and the
    // second card sits at 95% scale, twelve pixels up, which is very nearly
    // that same slot.
    //
    // The effect is the NEXT track's cover sitting in the place the flying one
    // is travelling to. So the stack stands down for the duration of the
    // transition: one card leaves, one card lands, nothing behind them.
    final routeAnimation = ModalRoute.of(context)?.animation;
    final inRouteTransition = routeAnimation != null &&
        routeAnimation.status != AnimationStatus.completed &&
        routeAnimation.status != AnimationStatus.dismissed;
    final deepest =
        inRouteTransition ? 0 : CardAnimationConfig.maxVisibleCards - 1;

    final cards = <Widget>[];
    for (var depth = deepest; depth >= shallowest; depth--) {
      final itemIndex = _trackAt(depth);
      if (itemIndex == null) continue;

      cards.add(
        depth == 0 && _s > 0
            ? _buildDepartingCard(itemIndex, shift)
            : depth == -1
                ? _buildArrivingCard(itemIndex, shift)
                : _buildStackedCard(itemIndex, depth, shift),
      );
    }

    return cards;
  }

  Widget _buildStackedCard(int itemIndex, int baseDepth, double shift) {
    final layout = layoutAt(
      baseDepth + shift,
      scaleFraction: CardAnimationConfig.scaleFraction,
      yOffset: CardAnimationConfig.yOffset,
    );

    final inFrontSlot = baseDepth == 0;
    // Going back, the card being covered is no longer the one the user is
    // acting on — the card arriving over it is. Two cards claiming that at
    // once would both pivot about the same grab point.
    final isActive = inFrontSlot && _s >= 0;

    return _transformed(
      // The front card slides a little under a backward drag: it is being
      // covered, not thrown.
      dx: inFrontSlot && _s < 0
          ? _s * _travel * CardAnimationConfig.backwardFollow
          : 0.0,
      dy: layout.dy,
      scale: layout.scale,
      rotation: 0,
      opacity: layout.opacity,
      child: widget.itemBuilder(context, itemIndex, isActive: isActive),
      isActive: isActive,
    );
  }

  /// The card being thrown away.
  Widget _buildDepartingCard(int itemIndex, double shift) {
    final t = _s.clamp(0.0, 1.0);
    final layout = layoutAt(
      shift,
      scaleFraction: CardAnimationConfig.scaleFraction,
      yOffset: CardAnimationConfig.yOffset,
    );

    return _transformed(
      dx: _s * _travel,
      // Lifts as it goes, on the same curve as everything else.
      dy: -CardAnimationConfig.throwLift * t,
      scale: layout.scale,
      rotation: t * CardAnimationConfig.throwRotationDeg,
      // Gone before it commits, so the reset at |s| = 1 has nothing to reveal.
      opacity: (1.0 - ((t - 0.55) / 0.4)).clamp(0.0, 1.0),
      child: widget.itemBuilder(context, itemIndex, isActive: true),
      isActive: true,
    );
  }

  /// The card being brought back, mirror image of the one being thrown.
  Widget _buildArrivingCard(int itemIndex, double shift) {
    final t = (-_s).clamp(0.0, 1.0);
    final remaining = 1.0 - t;
    final layout = layoutAt(
      -1 + shift,
      scaleFraction: CardAnimationConfig.scaleFraction,
      yOffset: CardAnimationConfig.yOffset,
    );

    return _transformed(
      dx: -_travel * remaining,
      dy: -CardAnimationConfig.throwLift * remaining,
      scale: layout.scale,
      rotation: -remaining * CardAnimationConfig.throwRotationDeg,
      opacity: 1.0,
      child: widget.itemBuilder(context, itemIndex, isActive: true),
      isActive: true,
    );
  }

  Widget _transformed({
    required double dx,
    required double dy,
    required double scale,
    required double rotation,
    required double opacity,
    required Widget child,
    required bool isActive,
  }) {
    final wrapped = RepaintBoundary(child: child);
    return Transform(
      transform: Matrix4.identity()
        ..translateByVector3(Vector3(dx, dy, 0.0))
        ..rotateZ(rotation * (math.pi / 180))
        ..scaleByVector3(Vector3.all(scale)),
      // Only a card under the finger pivots about the grab point; the rest of
      // the stack has no finger on it and turns about its middle.
      alignment: isActive ? _pivot : Alignment.center,
      child: opacity >= 1.0
          ? wrapped
          : Opacity(opacity: opacity.clamp(0.0, 1.0), child: wrapped),
    );
  }
}
