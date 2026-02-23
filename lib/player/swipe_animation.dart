import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
export 'swipe_animation.dart';

// ─── Configuration ──────────────────────────────────────────────────────────

class CardAnimationConfig {
  static const int maxVisibleCards = 4;

  /// Scale reduction per card depth level (5% smaller per level).
  static const double scaleFraction = 0.05;

  /// Vertical offset per card depth level (cards stack upward).
  static const double yOffset = 12.0;

  /// Horizontal drag threshold (fraction of screen width) to trigger throw.
  static const double swipeThreshold = 0.12;

  /// Duration of the throw animation (front card flies away).
  static const Duration throwDuration = Duration(milliseconds: 500);

  /// Duration of background cards popping up to fill the gap.
  static const Duration popUpDuration = Duration(milliseconds: 300);

  /// Rotation angle during throw (full 360°).
  static const double throwRotationDeg = 360.0;

  /// How far the card flies away (multiplier of screen dimension).
  static const double throwDistance = 1.6;
}

enum SwipeDirection { left, right }

// ─── Card Controller ────────────────────────────────────────────────────────

class CardController extends ChangeNotifier {
  final TickerProvider vsync;
  final Function(SwipeDirection) onSwipeComplete;
  Size screenSize;

  late AnimationController _throwController;
  late AnimationController _popUpController;

  // ── Throw animations (front card) ──
  late Animation<double> _throwSlideX;
  late Animation<double> _throwSlideY;
  late Animation<double> _throwRotation;
  late Animation<double> _throwScale;

  double get throwProgress => _throwController.value;
  double get popUpProgress => _popUpController.value;

  bool get isAnimating =>
      _throwController.isAnimating || _popUpController.isAnimating;

  SwipeDirection _direction = SwipeDirection.right;
  SwipeDirection get direction => _direction;

  /// Drag state.
  double _dragDx = 0.0;
  double _dragDy = 0.0;
  double get dragDx => _dragDx;
  double get dragDy => _dragDy;
  bool isDragging = false;

  bool _isControlAnimation = false;
  bool get isControlAnimation => _isControlAnimation;

  /// Gate drag-swipes at playlist boundaries.
  bool Function(SwipeDirection)? canSwipe;

  /// Whether the drag started on the right half of the card (affects rotation).
  bool _dragStartedRight = true;

  CardController({
    required this.vsync,
    required this.onSwipeComplete,
    required this.screenSize,
  }) {
    _throwController = AnimationController(
      vsync: vsync,
      duration: CardAnimationConfig.throwDuration,
    );
    _popUpController = AnimationController(
      vsync: vsync,
      duration: CardAnimationConfig.popUpDuration,
    );

    // Initialize with identity animations.
    _setupThrowAnimations(SwipeDirection.right);

    _throwController.addListener(notifyListeners);
    _popUpController.addListener(notifyListeners);
  }

  void updateScreenSize(Size newSize) {
    screenSize = newSize;
  }

  void _setupThrowAnimations(SwipeDirection dir) {
    final isRight = dir == SwipeDirection.right;

    // Card flies to the side and upward.
    final endX = (isRight ? 1 : -1) *
        screenSize.width *
        CardAnimationConfig.throwDistance;

    _throwSlideX = Tween<double>(begin: 0, end: endX).animate(
      CurvedAnimation(
        parent: _throwController,
        curve: const Interval(0, 0.8, curve: Curves.easeInQuad),
      ),
    );

    _throwSlideY = Tween<double>(begin: 0, end: -screenSize.height * 0.35)
        .animate(
      CurvedAnimation(
        parent: _throwController,
        curve: const Interval(0, 0.7, curve: Curves.easeOutQuad),
      ),
    );

    // 360° rotation, direction based on drag start position.
    final rotDeg = CardAnimationConfig.throwRotationDeg *
        (_dragStartedRight ? -1.0 : 1.0);
    _throwRotation = Tween<double>(begin: 0, end: rotDeg).animate(
      CurvedAnimation(
        parent: _throwController,
        curve: Curves.easeInOut,
      ),
    );

    // Shrink slightly as it flies.
    _throwScale = Tween<double>(begin: 1.0, end: 0.6).animate(
      CurvedAnimation(
        parent: _throwController,
        curve: const Interval(0, 0.6, curve: Curves.easeIn),
      ),
    );
  }

  // ── Gesture Handling ──

  void onPanStart(DragStartDetails details) {
    if (isAnimating) return;
    isDragging = true;
    _dragDx = 0;
    _dragDy = 0;
    // Determine rotation direction from start position.
    _dragStartedRight =
        details.localPosition.dx > screenSize.width * 0.5;
    notifyListeners();
  }

  void onPanUpdate(DragUpdateDetails details) {
    if (!isDragging) return;
    _dragDx += details.delta.dx;
    _dragDy += details.delta.dy;
    notifyListeners();
  }

  void onPanEnd(DragEndDetails details) {
    if (!isDragging) return;
    isDragging = false;

    final magnitude = _dragDx.abs() / screenSize.width;
    if (magnitude > CardAnimationConfig.swipeThreshold) {
      final dir =
          _dragDx > 0 ? SwipeDirection.right : SwipeDirection.left;

      if (canSwipe != null && !canSwipe!(dir)) {
        _snapBack();
        return;
      }

      _isControlAnimation = false;
      _launchThrow(dir);
    } else {
      _snapBack();
    }
  }

  void _snapBack() {
    _dragDx = 0;
    _dragDy = 0;
    notifyListeners();
  }

  void _launchThrow(SwipeDirection dir) {
    _direction = dir;
    _dragDx = 0;
    _dragDy = 0;
    _setupThrowAnimations(dir);
    _throwController.forward(from: 0);
    _popUpController.forward(from: 0);

    _throwController.addStatusListener(_onThrowComplete);
  }

  void _onThrowComplete(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _throwController.removeStatusListener(_onThrowComplete);
      onSwipeComplete(_direction);
    }
  }

  // ── Programmatic Animations ──

  void animateToNext() {
    if (isAnimating) return;
    _isControlAnimation = true;
    _dragStartedRight = true;
    _launchThrow(SwipeDirection.right);
  }

  void animateToPrevious() {
    if (isAnimating) return;
    _isControlAnimation = true;
    _dragStartedRight = false;
    _launchThrow(SwipeDirection.left);
  }

  void resetImmediate() {
    _throwController.reset();
    _popUpController.reset();
    _dragDx = 0;
    _dragDy = 0;
    isDragging = false;
    _isControlAnimation = false;
  }

  /// Transform values for the front card during throw.
  double get throwX => _throwSlideX.value;
  double get throwY => _throwSlideY.value;
  double get throwRotation => _throwRotation.value;
  double get throwScaleValue => _throwScale.value;

  @override
  void dispose() {
    _throwController.dispose();
    _popUpController.dispose();
    super.dispose();
  }
}

// ─── Animated Player Card Widget ────────────────────────────────────────────

class AnimatedPlayerCard extends StatefulWidget {
  final int itemCount;
  final int currentSongId;
  final Function(int) onPageChanged;
  final Widget Function(BuildContext, int, {bool isActive}) itemBuilder;
  final Function()? onNextTap;
  final Function()? onPreviousTap;

  const AnimatedPlayerCard({
    Key? key,
    required this.itemCount,
    required this.currentSongId,
    required this.onPageChanged,
    required this.itemBuilder,
    this.onNextTap,
    this.onPreviousTap,
  }) : super(key: key);

  @override
  AnimatedPlayerCardState createState() => AnimatedPlayerCardState();
}

class AnimatedPlayerCardState extends State<AnimatedPlayerCard>
    with TickerProviderStateMixin {
  late List<CardController> _cardControllers;
  Size _screenSize = Size.zero;
  int _currentIndex = 0;
  bool _animatingFromControls = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.currentSongId;
    _initializeCards();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _screenSize = MediaQuery.of(context).size;
          _updateControllerScreenSizes();
        });
      }
    });
  }

  void animateToNext() {
    if (_currentIndex < widget.itemCount - 1) {
      _animatingFromControls = true;
      _cardControllers[0].animateToNext();
    }
  }

  void animateToPrevious() {
    if (_currentIndex > 0) {
      _animatingFromControls = true;
      _cardControllers[0].animateToPrevious();
    }
  }

  @override
  void didUpdateWidget(AnimatedPlayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.itemCount > 0 && _currentIndex >= widget.itemCount) {
      setState(() {
        _currentIndex = widget.itemCount - 1;
      });
    }
    if (widget.currentSongId != _currentIndex && !_animatingFromControls) {
      setState(() {
        _currentIndex =
            widget.currentSongId.clamp(0, math.max(0, widget.itemCount - 1));
      });
    }
  }

  bool _canSwipe(SwipeDirection direction) {
    if (direction == SwipeDirection.right) {
      return _currentIndex < widget.itemCount - 1;
    }
    return _currentIndex > 0;
  }

  void _initializeCards() {
    _cardControllers = List.generate(
      CardAnimationConfig.maxVisibleCards,
      (index) => CardController(
        vsync: this,
        onSwipeComplete: _handleSwipeComplete,
        screenSize: _screenSize,
      )..canSwipe = _canSwipe,
    );
  }

  void _updateControllerScreenSizes() {
    for (var controller in _cardControllers) {
      controller.updateScreenSize(_screenSize);
    }
  }

  void _handleSwipeComplete(SwipeDirection direction) {
    final nextIndex = direction == SwipeDirection.right
        ? _currentIndex + 1
        : _currentIndex - 1;

    if (nextIndex >= 0 && nextIndex < widget.itemCount) {
      setState(() {
        _currentIndex = nextIndex;
      });
      if (!_animatingFromControls) {
        widget.onPageChanged(nextIndex);
      }
      _animatingFromControls = false;

      final swipedController = _cardControllers.removeAt(0);
      swipedController.resetImmediate();
      _cardControllers.add(swipedController);
    } else {
      _animatingFromControls = false;
      _cardControllers[0].resetImmediate();
    }
  }

  @override
  void dispose() {
    for (var controller in _cardControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frontCtrl = _cardControllers[0];

    return AnimatedBuilder(
      animation: Listenable.merge(_cardControllers),
      builder: (context, _) {
        final isThrowing = frontCtrl.isAnimating;
        final popProgress = Curves.easeOutBack
            .transform(frontCtrl.popUpProgress.clamp(0.0, 1.0));

        // During drag, compute a drag influence (0→1) for back card movement.
        final dragInfluence = frontCtrl.isDragging
            ? (frontCtrl.dragDx.abs() / (_screenSize.width * 0.4))
                .clamp(0.0, 1.0)
            : 0.0;
        final backProgress = isThrowing ? popProgress : dragInfluence * 0.3;

        final cards = <Widget>[];

        // Build back cards first (bottom of z-order), then front card on top.
        for (int i = CardAnimationConfig.maxVisibleCards - 1; i >= 0; i--) {
          final itemIndex = _currentIndex + i;
          if (itemIndex < 0 || itemIndex >= widget.itemCount) continue;

          if (i == 0) {
            // Front card — the one that gets thrown away.
            cards.add(
              _buildFrontCard(itemIndex, frontCtrl),
            );
          } else {
            // Background stacked cards — pop up during throw.
            cards.add(
              _buildBackCard(itemIndex, i, backProgress),
            );
          }
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // Back cards rendered first.
            ...cards.sublist(0, math.max(0, cards.length - 1)),
            // Front card on top with gesture detection.
            if (cards.isNotEmpty)
              GestureDetector(
                onPanStart: frontCtrl.onPanStart,
                onPanUpdate: frontCtrl.onPanUpdate,
                onPanEnd: frontCtrl.onPanEnd,
                child: cards.last,
              ),
          ],
        );
      },
    );
  }

  /// Front card: during idle shows normally, during throw it flies away
  /// with rotation, during drag it tilts slightly.
  Widget _buildFrontCard(int itemIndex, CardController ctrl) {
    if (ctrl.isAnimating) {
      // Throw animation — card flies away with rotation.
      return Transform(
        transform: Matrix4.identity()
          ..translateByVector3(Vector3(ctrl.throwX, ctrl.throwY, 0.0))
          ..rotateZ(ctrl.throwRotation * (math.pi / 180))
          ..scaleByVector3(Vector3.all(ctrl.throwScaleValue)),
        alignment: Alignment.center,
        child: Opacity(
          opacity: (1.0 - ctrl.throwProgress * 0.5).clamp(0.0, 1.0),
          child: widget.itemBuilder(context, itemIndex, isActive: true),
        ),
      );
    }

    if (ctrl.isDragging) {
      // Drag — card follows finger with subtle tilt.
      final tiltAngle = (ctrl.dragDx / _screenSize.width) * 0.15;
      return Transform(
        transform: Matrix4.identity()
          ..translateByVector3(Vector3(ctrl.dragDx * 0.6, ctrl.dragDy * 0.3, 0.0))
          ..rotateZ(tiltAngle),
        alignment: Alignment.center,
        child: widget.itemBuilder(context, itemIndex, isActive: true),
      );
    }

    // Idle — static front card.
    return widget.itemBuilder(context, itemIndex, isActive: true);
  }

  /// Background cards: stacked behind with cascading scale and vertical offset.
  /// During throw, they pop up and grow to fill the gap.
  Widget _buildBackCard(int depth, int depthIndex, double animProgress) {
    // Target state: each card moves up one level in the stack.
    // depth = 1 → becomes front (scale 1.0, offset 0)
    // depth = 2 → becomes depth 1 (scale 0.95, offset 12)
    // etc.
    final currentScale =
        1.0 - (depthIndex * CardAnimationConfig.scaleFraction);
    final targetScale =
        1.0 - ((depthIndex - 1) * CardAnimationConfig.scaleFraction);
    final scale = currentScale + (targetScale - currentScale) * animProgress;

    final currentY = -depthIndex * CardAnimationConfig.yOffset;
    final targetY = -(depthIndex - 1) * CardAnimationConfig.yOffset;
    final yOff = currentY + (targetY - currentY) * animProgress;

    final opacity =
        (1.0 - (depthIndex * 0.15) + animProgress * 0.15).clamp(0.0, 1.0);

    return Transform(
      transform: Matrix4.identity()
        ..translateByVector3(Vector3(0.0, yOff, 0.0))
        ..scaleByVector3(Vector3.all(scale)),
      alignment: Alignment.center,
      child: Opacity(
        opacity: opacity,
        child: widget.itemBuilder(context, depth, isActive: false),
      ),
    );
  }
}
