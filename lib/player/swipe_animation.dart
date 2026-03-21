import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
export 'swipe_animation.dart';

// ─── Configuration ──────────────────────────────────────────────────────────

class CardAnimationConfig {
  static const int maxVisibleCards = 4;
  static const double scaleFraction = 0.05;
  static const double yOffset = 12.0;

  /// Fraction of screen width to count as a swipe.
  static const double swipeThreshold = 0.15;

  /// Minimum fling velocity (px/s) to trigger a swipe regardless of distance.
  static const double flingVelocity = 600.0;

  static const Duration throwDuration = Duration(milliseconds: 380);
  static const Duration popUpDuration = Duration(milliseconds: 350);
  static const Duration snapBackDuration = Duration(milliseconds: 250);

  /// Rotation during throw (degrees).
  static const double throwRotationDeg = 25.0;

  /// How far the card flies off (multiplier of screen width).
  static const double throwDistance = 1.5;

  /// Max tilt angle during drag (radians).
  static const double maxDragTilt = 0.08;
}

enum SwipeDirection { left, right }

// ─── Card Controller ────────────────────────────────────────────────────────

class CardController extends ChangeNotifier {
  final TickerProvider vsync;
  final Function(SwipeDirection) onSwipeComplete;
  Size screenSize;

  late AnimationController _throwController;
  late AnimationController _popUpController;
  late AnimationController _snapBackController;

  // Throw animations
  late Animation<double> _throwSlideX;
  late Animation<double> _throwSlideY;
  late Animation<double> _throwRotation;
  late Animation<double> _throwOpacity;

  double get throwProgress => _throwController.value;
  double get popUpProgress => _popUpController.value;

  bool get isAnimating =>
      _throwController.isAnimating ||
      _popUpController.isAnimating ||
      _snapBackController.isAnimating;

  SwipeDirection _direction = SwipeDirection.right;
  SwipeDirection get direction => _direction;

  // Drag state
  double _dragDx = 0.0;
  double _dragDy = 0.0;
  double get dragDx => _dragDx;
  double get dragDy => _dragDy;
  bool isDragging = false;

  bool _isControlAnimation = false;
  bool get isControlAnimation => _isControlAnimation;

  bool Function(SwipeDirection)? canSwipe;

  // Snap-back animated values
  double _snapStartDx = 0.0;
  double _snapStartDy = 0.0;

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
    _snapBackController = AnimationController(
      vsync: vsync,
      duration: CardAnimationConfig.snapBackDuration,
    );

    _setupThrowAnimations(SwipeDirection.right, 0.0);

    _throwController.addListener(notifyListeners);
    _popUpController.addListener(notifyListeners);
    _snapBackController.addListener(() {
      // Interpolate drag back to zero
      final t = Curves.easeOutCubic.transform(_snapBackController.value);
      _dragDx = _snapStartDx * (1.0 - t);
      _dragDy = _snapStartDy * (1.0 - t);
      notifyListeners();
    });
  }

  void updateScreenSize(Size newSize) => screenSize = newSize;

  void _setupThrowAnimations(SwipeDirection dir, double startDx) {
    final isRight = dir == SwipeDirection.right;
    final endX =
        (isRight ? 1 : -1) *
        screenSize.width *
        CardAnimationConfig.throwDistance;

    _throwSlideX = Tween<double>(begin: startDx, end: endX).animate(
      CurvedAnimation(parent: _throwController, curve: Curves.easeInCubic),
    );
    _throwSlideY = Tween<double>(
      begin: _dragDy * 0.3,
      end: -40.0,
    ).animate(CurvedAnimation(parent: _throwController, curve: Curves.easeOut));

    final rotDeg =
        CardAnimationConfig.throwRotationDeg * (isRight ? 1.0 : -1.0);
    _throwRotation = Tween<double>(begin: 0, end: rotDeg).animate(
      CurvedAnimation(parent: _throwController, curve: Curves.easeInOut),
    );
    _throwOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _throwController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
      ),
    );
  }

  // ── Gestures ──

  void onPanStart(DragStartDetails details) {
    if (isAnimating) return;
    isDragging = true;
    _dragDx = 0;
    _dragDy = 0;
    _snapBackController.reset();
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

    final velocity = details.velocity.pixelsPerSecond.dx;
    final distance = _dragDx.abs() / screenSize.width;
    final isFling = velocity.abs() > CardAnimationConfig.flingVelocity;
    final isPastThreshold = distance > CardAnimationConfig.swipeThreshold;

    if (isFling || isPastThreshold) {
      final dir = (isFling ? velocity > 0 : _dragDx > 0)
          ? SwipeDirection.right
          : SwipeDirection.left;

      if (canSwipe != null && !canSwipe!(dir)) {
        _animateSnapBack();
        return;
      }

      _isControlAnimation = false;
      _launchThrow(dir, _dragDx);
    } else {
      _animateSnapBack();
    }
  }

  void _animateSnapBack() {
    _snapStartDx = _dragDx;
    _snapStartDy = _dragDy;
    _snapBackController.forward(from: 0);
  }

  void _launchThrow(SwipeDirection dir, double startDx) {
    _direction = dir;
    _setupThrowAnimations(dir, startDx);
    _dragDx = 0;
    _dragDy = 0;
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

  // ── Programmatic ──

  void animateToNext() {
    if (isAnimating) return;
    _isControlAnimation = true;
    _launchThrow(SwipeDirection.right, 0.0);
  }

  void animateToPrevious() {
    if (isAnimating) return;
    _isControlAnimation = true;
    _launchThrow(SwipeDirection.left, 0.0);
  }

  void resetImmediate() {
    _throwController.reset();
    _popUpController.reset();
    _snapBackController.reset();
    _dragDx = 0;
    _dragDy = 0;
    isDragging = false;
    _isControlAnimation = false;
  }

  double get throwX => _throwSlideX.value;
  double get throwY => _throwSlideY.value;
  double get throwRotation => _throwRotation.value;
  double get throwOpacity => _throwOpacity.value;

  @override
  void dispose() {
    _throwController.dispose();
    _popUpController.dispose();
    _snapBackController.dispose();
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
      setState(() => _currentIndex = widget.itemCount - 1);
    }
    // Only snap index if no animation is in progress — during animated
    // transitions the card deck manages its own index via _handleSwipeComplete.
    final anyAnimating = _cardControllers.any((c) => c.isAnimating);
    if (widget.currentSongId != _currentIndex &&
        !_animatingFromControls &&
        !anyAnimating) {
      setState(() {
        _currentIndex = widget.currentSongId.clamp(
          0,
          math.max(0, widget.itemCount - 1),
        );
      });
    }
  }

  bool _canSwipe(SwipeDirection direction) {
    // Only allow forward (right) swipe — the card stack shows next songs only.
    // Previous is handled by the prev button directly (no card animation).
    if (direction == SwipeDirection.right) {
      return _currentIndex < widget.itemCount - 1;
    }
    return false;
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
    for (var c in _cardControllers) {
      c.updateScreenSize(_screenSize);
    }
  }

  void _handleSwipeComplete(SwipeDirection direction) {
    final nextIndex = direction == SwipeDirection.right
        ? _currentIndex + 1
        : _currentIndex - 1;

    if (nextIndex >= 0 && nextIndex < widget.itemCount) {
      setState(() => _currentIndex = nextIndex);
      // Always notify — this triggers controller.next()/prev() to change the track
      widget.onPageChanged(nextIndex);
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
    for (var c in _cardControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frontCtrl = _cardControllers[0];

    return AnimatedBuilder(
      animation: Listenable.merge(_cardControllers),
      builder: (context, _) {
        final isThrowing = frontCtrl.isAnimating && !frontCtrl.isDragging;
        final popProgress = Curves.easeOutCubic.transform(
          frontCtrl.popUpProgress.clamp(0.0, 1.0),
        );

        // Back cards respond to drag AND throw
        final dragInfluence = frontCtrl.isDragging
            ? (frontCtrl.dragDx.abs() / (_screenSize.width * 0.5)).clamp(
                0.0,
                1.0,
              )
            : 0.0;
        final backProgress = isThrowing ? popProgress : dragInfluence * 0.4;

        final cards = <Widget>[];

        for (int i = CardAnimationConfig.maxVisibleCards - 1; i >= 0; i--) {
          final itemIndex = _currentIndex + i;
          if (itemIndex < 0 || itemIndex >= widget.itemCount) continue;

          if (i == 0) {
            cards.add(_buildFrontCard(itemIndex, frontCtrl));
          } else {
            cards.add(_buildBackCard(itemIndex, i, backProgress));
          }
        }

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: frontCtrl.onPanStart,
          onPanUpdate: frontCtrl.onPanUpdate,
          onPanEnd: frontCtrl.onPanEnd,
          child: Stack(fit: StackFit.expand, children: cards),
        );
      },
    );
  }

  Widget _buildFrontCard(int itemIndex, CardController ctrl) {
    final child = RepaintBoundary(
      child: widget.itemBuilder(context, itemIndex, isActive: true),
    );

    if (ctrl.isAnimating && !ctrl.isDragging) {
      // Throw — card flies away
      return Transform(
        transform: Matrix4.identity()
          ..translateByVector3(Vector3(ctrl.throwX, ctrl.throwY, 0.0))
          ..rotateZ(ctrl.throwRotation * (math.pi / 180)),
        alignment: Alignment.center,
        child: Opacity(
          opacity: ctrl.throwOpacity.clamp(0.0, 1.0),
          child: child,
        ),
      );
    }

    // Drag or snap-back — card follows finger 1:1
    if (ctrl.dragDx.abs() > 0.5 || ctrl.dragDy.abs() > 0.5) {
      final tilt =
          (ctrl.dragDx / _screenSize.width) * CardAnimationConfig.maxDragTilt;
      return Transform(
        transform: Matrix4.identity()
          ..translateByVector3(Vector3(ctrl.dragDx, ctrl.dragDy * 0.4, 0.0))
          ..rotateZ(tilt),
        alignment: Alignment.center,
        child: child,
      );
    }

    return child;
  }

  Widget _buildBackCard(int depth, int depthIndex, double animProgress) {
    final currentScale = 1.0 - (depthIndex * CardAnimationConfig.scaleFraction);
    final targetScale =
        1.0 - ((depthIndex - 1) * CardAnimationConfig.scaleFraction);
    final scale = currentScale + (targetScale - currentScale) * animProgress;

    final currentY = -depthIndex * CardAnimationConfig.yOffset;
    final targetY = -(depthIndex - 1) * CardAnimationConfig.yOffset;
    final yOff = currentY + (targetY - currentY) * animProgress;

    final opacity = (1.0 - depthIndex * 0.12 + animProgress * 0.12).clamp(
      0.0,
      1.0,
    );

    return Transform(
      transform: Matrix4.identity()
        ..translateByVector3(Vector3(0.0, yOff, 0.0))
        ..scaleByVector3(Vector3.all(scale)),
      alignment: Alignment.center,
      child: Opacity(
        opacity: opacity,
        child: RepaintBoundary(
          child: widget.itemBuilder(context, depth, isActive: false),
        ),
      ),
    );
  }
}
