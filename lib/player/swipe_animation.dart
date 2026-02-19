import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
export 'swipe_animation.dart';

// Animation Configuration
class CardAnimationConfig {
  static const double actionThreshold = 0.8;
  static const double swipeThreshold = 0.4;
  static const double maxAngle = 35;
  static const int maxVisibleCards = 3;
  static const double stackedCardScale = 0.95;
  static const double stackedCardOffset = 8.0;
  // Snap-back duration (drag release, reset)
  static const Duration snapDuration = Duration(milliseconds: 200);
  // Control-triggered deal animation
  static const Duration dealDuration = Duration(milliseconds: 420);
}

// Card Controller
class CardController extends ChangeNotifier {
  final TickerProvider vsync;
  final Function(SwipeDirection) onSwipeComplete;
  Size screenSize;
  late AnimationController _animationController;
  late Animation<Offset> _positionAnimation;
  late Animation<double> _angleAnimation;

  Offset position = Offset.zero;
  double angle = 0.0;
  bool isDragging = false;
  bool _isControlAnimation = false;

  /// Set by AnimatedPlayerCardState to gate drag-swipes at playlist boundaries.
  bool Function(SwipeDirection)? canSwipe;

  bool get isControlAnimation => _isControlAnimation;
  double get animationProgress => _animationController.value;

  CardController({
    required this.vsync,
    required this.onSwipeComplete,
    required this.screenSize,
  }) {
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      vsync: vsync,
      duration: CardAnimationConfig.snapDuration,
    );

    _positionAnimation = _animationController.drive(
      Tween<Offset>(begin: Offset.zero, end: Offset.zero),
    );

    _angleAnimation = _animationController.drive(
      Tween<double>(begin: 0.0, end: 0.0),
    );

    _animationController.addListener(() {
      position = _positionAnimation.value;
      angle = _angleAnimation.value;
      notifyListeners();
    });
  }

  void updateScreenSize(Size newSize) {
    screenSize = newSize;
  }

  void onPanStart(DragStartDetails details) {
    isDragging = true;
    notifyListeners();
  }

  void onPanUpdate(DragUpdateDetails details) {
    position += details.delta;
    angle =
        (position.dx / screenSize.width) *
        (math.pi / 180) *
        CardAnimationConfig.maxAngle;
    notifyListeners();
  }

  void onPanEnd(DragEndDetails details) {
    isDragging = false;
    final swipeMagnitude = position.dx.abs() / screenSize.width;

    if (swipeMagnitude > CardAnimationConfig.swipeThreshold) {
      final direction = position.dx > 0
          ? SwipeDirection.right
          : SwipeDirection.left;

      // Don't fly off screen if there's no song in that direction.
      if (canSwipe != null && !canSwipe!(direction)) {
        reset();
        notifyListeners();
        return;
      }

      final endX = direction == SwipeDirection.right
          ? screenSize.width * 1.5
          : -screenSize.width * 1.5;

      _positionAnimation = _animationController.drive(
        Tween<Offset>(begin: position, end: Offset(endX, position.dy)),
      );

      _angleAnimation = _animationController.drive(
        Tween<double>(begin: angle, end: angle * 2),
      );

      _animationController.forward().then((_) => onSwipeComplete(direction));
    } else {
      reset();
    }
    notifyListeners();
  }

  void reset() {
    _isControlAnimation = false;
    _animationController.duration = CardAnimationConfig.snapDuration;

    _positionAnimation = _animationController.drive(
      Tween<Offset>(begin: position, end: Offset.zero),
    );

    _angleAnimation = _animationController.drive(
      Tween<double>(begin: angle, end: 0.0),
    );

    _animationController.forward(from: 0);
  }

  void animateToNext() {
    _isControlAnimation = true;
    _animationController.duration = CardAnimationConfig.dealDuration;

    final endX = screenSize.width * 1.5;
    final liftY = -screenSize.height * 0.06;

    _positionAnimation = _animationController.drive(
      Tween<Offset>(begin: Offset.zero, end: Offset(endX, liftY))
          .chain(CurveTween(curve: Curves.easeInCubic)),
    );

    _angleAnimation = _animationController.drive(
      Tween<double>(
        begin: 0.0,
        end: CardAnimationConfig.maxAngle * 0.7 * (math.pi / 180),
      ).chain(CurveTween(curve: Curves.easeInQuad)),
    );

    _animationController.forward(from: 0).then((_) {
      _animationController.duration = CardAnimationConfig.snapDuration;
      _isControlAnimation = false;
      onSwipeComplete(SwipeDirection.right);
    });
  }

  void animateToPrevious() {
    _isControlAnimation = true;
    _animationController.duration = CardAnimationConfig.dealDuration;

    final endX = -screenSize.width * 1.5;
    final liftY = -screenSize.height * 0.06;

    _positionAnimation = _animationController.drive(
      Tween<Offset>(begin: Offset.zero, end: Offset(endX, liftY))
          .chain(CurveTween(curve: Curves.easeInCubic)),
    );

    _angleAnimation = _animationController.drive(
      Tween<double>(
        begin: 0.0,
        end: -CardAnimationConfig.maxAngle * 0.7 * (math.pi / 180),
      ).chain(CurveTween(curve: Curves.easeInQuad)),
    );

    _animationController.forward(from: 0).then((_) {
      _animationController.duration = CardAnimationConfig.snapDuration;
      _isControlAnimation = false;
      onSwipeComplete(SwipeDirection.left);
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}

// Animated Player Card Widget
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

  /// Called externally (from Controls) to animate card swipe to next
  void animateToNext() {
    if (_currentIndex < widget.itemCount - 1) {
      _animatingFromControls = true;
      _cardControllers[0].animateToNext();
    }
  }

  /// Called externally (from Controls) to animate card swipe to previous
  void animateToPrevious() {
    if (_currentIndex > 0) {
      _animatingFromControls = true;
      _cardControllers[0].animateToPrevious();
    }
  }

  @override
  void didUpdateWidget(AnimatedPlayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clamp _currentIndex if the song list shrank
    if (widget.itemCount > 0 && _currentIndex >= widget.itemCount) {
      setState(() {
        _currentIndex = widget.itemCount - 1;
      });
    }
    // Sync index if changed externally (e.g. processingStateStream auto-advance)
    if (widget.currentSongId != _currentIndex && !_animatingFromControls) {
      setState(() {
        _currentIndex = widget.currentSongId.clamp(0, math.max(0, widget.itemCount - 1));
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
      // Only fire onPageChanged for user swipe, not control-triggered animation
      if (!_animatingFromControls) {
        widget.onPageChanged(nextIndex);
      }
      _animatingFromControls = false;

      final swipedController = _cardControllers.removeAt(0);
      swipedController.reset();
      _cardControllers.add(swipedController);
    } else {
      _animatingFromControls = false;
      _cardControllers[0].reset();
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

    return Stack(
      fit: StackFit.expand,
      children: List.generate(CardAnimationConfig.maxVisibleCards, (index) {
        final itemIndex = _currentIndex + index;
        if (itemIndex < 0 || itemIndex >= widget.itemCount) {
          return const SizedBox.shrink();
        }

        return Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // All cards listen to the front card so back cards can
              // animate forward when the front card is dealt away.
              return AnimatedBuilder(
                animation: index == 0
                    ? frontCtrl
                    : Listenable.merge([_cardControllers[index], frontCtrl]),
                builder: (context, child) {
                  // Back cards slide toward the front during control animations
                  double ei = index.toDouble();
                  if (index > 0 && frontCtrl.isControlAnimation) {
                    final p = Curves.easeOutCubic
                        .transform(frontCtrl.animationProgress);
                    ei = index - p;
                  }

                  final scale = math
                      .pow(CardAnimationConfig.stackedCardScale, ei)
                      .toDouble();
                  final stackOff =
                      ei * CardAnimationConfig.stackedCardOffset;

                  return Transform(
                    transform: Matrix4.identity()
                      ..translateByVector3(Vector3(
                        (index == 0 ? frontCtrl.position.dx : 0) + stackOff,
                        (index == 0 ? frontCtrl.position.dy : 0) + stackOff,
                        0.0,
                      ))
                      ..rotateZ(index == 0 ? frontCtrl.angle : 0.0)
                      ..scaleByVector3(
                          Vector3.all(scale - (ei * 0.05))),
                    alignment: Alignment.center,
                    child: Opacity(
                      opacity: (1.0 - (ei * 0.2)).clamp(0.0, 1.0),
                      child: Stack(
                        children: [
                          child!,
                          if (index == 0 && frontCtrl.isDragging)
                            _buildSwipeIndicators(frontCtrl.position.dx),
                        ],
                      ),
                    ),
                  );
                },
                child: index == 0
                    ? GestureDetector(
                        onPanStart: _cardControllers[0].onPanStart,
                        onPanUpdate: _cardControllers[0].onPanUpdate,
                        onPanEnd: _cardControllers[0].onPanEnd,
                        child: widget.itemBuilder(
                          context,
                          itemIndex,
                          isActive: true,
                        ),
                      )
                    : widget.itemBuilder(context, itemIndex, isActive: false),
              );
            },
          ),
        );
      }).reversed.toList(),
    );
  }

  Widget _buildSwipeIndicators(double dx) {
    final swipeProgress = dx.abs() / (_screenSize.width * 0.5);
    final opacity = (swipeProgress * 0.8).clamp(0.0, 1.0);

    return Stack(
      children: [
        if (dx > 20)
          Positioned(
            top: 20,
            right: 20,
            child: Transform.rotate(
              angle: -math.pi / 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Opacity(
                  opacity: opacity,
                  child: const Text(
                    'NEXT',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (dx < -20)
          Positioned(
            top: 20,
            left: 20,
            child: Transform.rotate(
              angle: math.pi / 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red, width: 4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Opacity(
                  opacity: opacity,
                  child: const Text(
                    'PREVIOUS',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

enum SwipeDirection { left, right }
