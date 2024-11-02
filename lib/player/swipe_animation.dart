import 'dart:math' as math;
import 'package:flutter/material.dart';
export 'swipe_animation.dart' show AnimatedPlayerCardState;

// Animation Configuration
class CardAnimationConfig {
  static const double actionThreshold = 0.8;
  static const double swipeThreshold = 0.4;
  static const double maxAngle = 35;
  static const int maxVisibleCards = 3;
  static const double stackedCardScale = 0.95;
  static const double stackedCardOffset = 8.0;
  static const Duration animationDuration = Duration(milliseconds: 200);
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
      duration: CardAnimationConfig.animationDuration,
    );

    _positionAnimation = _animationController.drive(Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ));

    _angleAnimation = _animationController.drive(Tween<double>(
      begin: 0.0,
      end: 0.0,
    ));

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
    angle = (position.dx / screenSize.width) *
        (math.pi / 180) *
        CardAnimationConfig.maxAngle;
    notifyListeners();
  }

  void onPanEnd(DragEndDetails details) {
    isDragging = false;
    final swipeMagnitude = position.dx.abs() / screenSize.width;

    if (swipeMagnitude > CardAnimationConfig.swipeThreshold) {
      final direction =
          position.dx > 0 ? SwipeDirection.right : SwipeDirection.left;
      final endX = direction == SwipeDirection.right
          ? screenSize.width * 1.5
          : -screenSize.width * 1.5;

      _positionAnimation = _animationController.drive(Tween<Offset>(
        begin: position,
        end: Offset(endX, position.dy),
      ));

      _angleAnimation = _animationController.drive(Tween<double>(
        begin: angle,
        end: angle * 2,
      ));

      _animationController.forward().then((_) => onSwipeComplete(direction));
    } else {
      reset();
    }
    notifyListeners();
  }

  void reset() {
    _positionAnimation = _animationController.drive(Tween<Offset>(
      begin: position,
      end: Offset.zero,
    ));

    _angleAnimation = _animationController.drive(Tween<double>(
      begin: angle,
      end: 0.0,
    ));

    _animationController.forward(from: 0);
  }

  void animateToNext() {
    final endX = screenSize.width * 1.5;
    _positionAnimation = _animationController.drive(Tween<Offset>(
      begin: Offset.zero,
      end: Offset(endX, 0),
    ));

    _angleAnimation = _animationController.drive(Tween<double>(
      begin: 0.0,
      end: CardAnimationConfig.maxAngle * (math.pi / 180),
    ));

    _animationController.forward(from: 0).then((_) {
      onSwipeComplete(SwipeDirection.right);
    });
  }

  void animateToPrevious() {
    final endX = -screenSize.width * 1.5;
    _positionAnimation = _animationController.drive(Tween<Offset>(
      begin: Offset.zero,
      end: Offset(endX, 0),
    ));

    _angleAnimation = _animationController.drive(Tween<double>(
      begin: 0.0,
      end: -CardAnimationConfig.maxAngle * (math.pi / 180),
    ));

    _animationController.forward(from: 0).then((_) {
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
  State<AnimatedPlayerCard> createState() => _AnimatedPlayerCardState();
}

class _AnimatedPlayerCardState extends State<AnimatedPlayerCard>
    with TickerProviderStateMixin {
  late List<CardController> _cardControllers;
  Size _screenSize = Size.zero;
  int _currentIndex = 0;

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
      _cardControllers[0].animateToNext();
    }
  }

  void animateToPrevious() {
    if (_currentIndex > 0) {
      _cardControllers[0].animateToPrevious();
    }
  }

  void _initializeCards() {
    _cardControllers = List.generate(
      CardAnimationConfig.maxVisibleCards,
      (index) => CardController(
        vsync: this,
        onSwipeComplete: _handleSwipeComplete,
        screenSize: _screenSize,
      ),
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
      widget.onPageChanged(nextIndex);

      final swipedController = _cardControllers.removeAt(0);
      swipedController.reset();
      _cardControllers.add(swipedController);
    } else {
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
    return Stack(
      children: List.generate(CardAnimationConfig.maxVisibleCards, (index) {
        final itemIndex = _currentIndex + index;
        if (itemIndex >= widget.itemCount) return const SizedBox.shrink();

        return Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return AnimatedBuilder(
                animation: _cardControllers[index],
                builder: (context, child) {
                  final scale = math
                      .pow(CardAnimationConfig.stackedCardScale, index)
                      .toDouble();
                  final offset = index * CardAnimationConfig.stackedCardOffset;

                  return Transform(
                    transform: Matrix4.identity()
                      ..translate(
                        _cardControllers[index].position.dx + offset,
                        _cardControllers[index].position.dy +
                            (index * CardAnimationConfig.stackedCardOffset),
                        0.0,
                      )
                      ..rotateZ(_cardControllers[index].angle)
                      ..scale(scale - (index * 0.05)),
                    alignment: Alignment.center,
                    child: Opacity(
                      opacity: 1.0 - (index * 0.2),
                      child: Stack(
                        children: [
                          child!,
                          if (index == 0 && _cardControllers[0].isDragging)
                            _buildSwipeIndicators(
                                _cardControllers[0].position.dx),
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
                        child: widget.itemBuilder(context, itemIndex,
                            isActive: true),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
