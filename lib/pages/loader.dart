import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Helpers/fileloader.dart';
import '../Routes/routes.dart';
import '../controllers/PlayerController.dart';

class AssetLoader extends StatefulWidget {
  const AssetLoader({super.key});

  @override
  State<AssetLoader> createState() => _AssetLoaderState();
}

class _AssetLoaderState extends State<AssetLoader>
    with TickerProviderStateMixin {
  static const int _rippleCount = 7;
  static const Duration _animationDuration = Duration(milliseconds: 2000);
  static const Duration _loadingDelay = Duration(seconds: 3);

  late final List<Ripple> _ripples;
  late final AnimationController _rotationController;
  late final AnimationController _pulseController;
  late final AnimationController _scanTextController;
  late final AnimationController _scaleController;
  late final AnimationController _shimmerController;
  bool _isNavigating = false;
  int _currentTextIndex = 0;
  double _progress = 0.0;
  Timer? _progressTimer;
  Timer? _textTimer;

  final List<String> _scanningTexts = [
    'Preparing Your Library',
    'Loading Audio Files',
    'Organizing Playlists',
    'Processing Metadata',
    'Almost Ready...'
  ];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadAssets();
    _startTextAnimation();
    _startProgressAnimation();
  }

  void _initializeAnimations() {
    // Ripple animations
    _ripples = List.generate(
      _rippleCount,
      (i) => Ripple(
        controller: AnimationController(
          vsync: this,
          duration: _animationDuration,
        )..addListener(() {
            if (mounted && i == 0) setState(() {});
          }),
      ),
    );

    // Rotation animation
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    // Pulse animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Text animation
    _scanTextController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // Scale animation
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // Shimmer animation
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _startRippleAnimations();
  }

  void _startProgressAnimation() {
    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (mounted && !_isNavigating) {
        setState(() {
          _progress = math.min(1.0, _progress + 0.01);
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _startTextAnimation() {
    _scanTextController.forward();
    _textTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted && !_isNavigating) {
        _scanTextController.reverse().then((_) {
          if (mounted) {
            setState(() {
              _currentTextIndex =
                  (_currentTextIndex + 1) % _scanningTexts.length;
            });
            _scanTextController.forward();
          }
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _startRippleAnimations() {
    for (int i = 0; i < _ripples.length; i++) {
      Future.delayed(Duration(milliseconds: i * 300), () {
        if (mounted) {
          _ripples[i].controller.repeat();
        }
      });
    }
  }

  Future<void> _loadAssets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await fetchMetaData(context);
      await prefs.setBool("artworkLoaded", true);

      Future.delayed(_loadingDelay, () {
        if (mounted && !_isNavigating) {
          _isNavigating = true;
          Navigator.pushReplacementNamed(context, Routes.home);
        }
      });
    } catch (e) {
      debugPrint('Error loading assets: $e');
      // Show error state
      _showErrorDialog();
    }
  }

  void _showErrorDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Loading Error'),
        content: const Text('Failed to load assets. Please try again.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _loadAssets();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _textTimer?.cancel();
    for (var ripple in _ripples) {
      ripple.controller.dispose();
    }
    _rotationController.dispose();
    _pulseController.dispose();
    _scanTextController.dispose();
    _scaleController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final shortestSide = math.min(size.width, size.height);
    final imageSize = shortestSide * 0.4; // Responsive image size

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black,
              Colors.orange.shade600,
              Colors.green.shade900,
              Colors.black,
            ],
            stops: const [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: Consumer<PlayerController>(
            builder: (context, playerController, _) => Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Padding(
                        padding: EdgeInsets.all(shortestSide * 0.05),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildAnimatedLogo(imageSize),
                            SizedBox(height: shortestSide * 0.08),
                            _buildLoadingText(shortestSide),
                            SizedBox(height: shortestSide * 0.04),
                            _buildProgressBar(size.width * 0.8),
                            SizedBox(height: shortestSide * 0.04),
                            _buildProgressIndicator(shortestSide * 0.12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedLogo(double size) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Rotating gradient rings
        ...List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _rotationController,
            builder: (context, child) {
              return Transform.rotate(
                angle: _rotationController.value * 2 * math.pi * (index + 1),
                child: Container(
                  width: size + (index * 20),
                  height: size + (index * 20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        Colors.green.withOpacity(0.3 - (index * 0.1)),
                        Colors.orange.withOpacity(0.3 - (index * 0.1)),
                        Colors.green.withOpacity(0.3 - (index * 0.1)),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        }),
        // Ripple effect
        CustomPaint(
          size: Size(size, size),
          painter: RipplePainter(_ripples),
        ),
        // Animated scale container
        AnimatedBuilder(
          animation: _scaleController,
          builder: (context, child) {
            return Transform.scale(
              scale: 1 + (_scaleController.value * 0.05),
              child: child,
            );
          },
          child: Container(
            width: size * 0.9,
            height: size * 0.9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.45),
              child: Image.asset(
                "assets/audio.jpeg",
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingText(double shortestSide) {
    final textScale = shortestSide / 400; // Base scale on screen size

    return AnimatedBuilder(
      animation: _scanTextController,
      builder: (context, child) {
        return Opacity(
          opacity: _scanTextController.value,
          child: Column(
            children: [
              Text(
                _scanningTexts[_currentTextIndex],
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24 * textScale,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 10 * textScale),
              ShimmerText(
                text: Provider.of<PlayerController>(context).textHeader,
                controller: _shimmerController,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 16 * textScale,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProgressBar(double width) {
    return Container(
      width: width,
      height: 4,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        color: Colors.white.withOpacity(0.1),
      ),
      child: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: width * _progress,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                colors: [
                  Colors.green.shade400,
                  Colors.orange.shade400,
                ],
              ),
            ),
          ),
          // Shimmer effect
          AnimatedBuilder(
            animation: _shimmerController,
            builder: (context, child) {
              return Positioned(
                left: width * _shimmerController.value - 50,
                child: Container(
                  width: 50,
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0),
                        Colors.white.withOpacity(0.5),
                        Colors.white.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator(double size) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color:
                  Colors.amber.withOpacity(0.5 + _pulseController.value * 0.5),
              width: 2,
            ),
          ),
          child: Center(
            child: SizedBox(
              width: size * 0.6,
              height: size * 0.6,
              child: const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                strokeWidth: 2,
              ),
            ),
          ),
        );
      },
    );
  }
}

class Ripple {
  final AnimationController controller;
  const Ripple({required this.controller});
}

class RipplePainter extends CustomPainter {
  final List<Ripple> ripples;

  RipplePainter(this.ripples);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    for (var ripple in ripples) {
      final value = ripple.controller.value;
      final maxRadius = size.width / 2;
      final radius = maxRadius * value;
      final opacity = (1 - value).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = Colors.blue.withOpacity(opacity * 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(RipplePainter oldDelegate) => true;
}

class ShimmerText extends StatelessWidget {
  final String text;
  final AnimationController controller;
  final TextStyle? style;

  const ShimmerText({
    Key? key,
    required this.text,
    required this.controller,
    this.style,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [
                Colors.white.withOpacity(0.5),
                Colors.white,
                Colors.white.withOpacity(0.5),
              ],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              transform: GradientRotation(controller.value * 2 * math.pi),
            ).createShader(bounds);
          },
          child: Text(
            text,
            style: style,
            textAlign: TextAlign.center,
          ),
        );
      },
    );
  }
}
