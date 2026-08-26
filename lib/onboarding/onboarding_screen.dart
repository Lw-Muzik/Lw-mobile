import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../controllers/app_controller.dart';
import 'onboarding_data.dart';

/// EQ-mode onboarding: focused pages for equalizer-only usage.
const _eqOnboardingPages = [
  OnboardingPage(
    title: 'Your Sound,\nYour Rules',
    subtitle: 'Professional audio for every app',
    icon: Icons.tune_rounded,
    features: [
      'EQ applies to Spotify, YouTube & more',
      'Runs silently in the background',
      'One-tap enable from notification',
    ],
    accentColor: Color(0xFF5EC4D4),
  ),
];

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final AppMode mode;
  const OnboardingScreen({
    super.key,
    required this.onComplete,
    this.mode = AppMode.musicPlayer,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _bgController;
  late final AnimationController _pulseController;
  late final List<OnboardingPage> _pages;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();

    // Build page list based on mode
    if (widget.mode == AppMode.equalizer) {
      _pages = [
        ..._eqOnboardingPages,
        onboardingPages[2], // Studio-Grade Equalizer
        onboardingPages[3], // Room Effects & Spatial Audio
      ];
    } else {
      _pages = onboardingPages;
    }

    _pageController = PageController();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarBrightness: Brightness.dark),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _bgController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _finish();
    }
  }

  void _skip() => _finish();

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(
        children: [
          // Animated gradient background
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, _) {
              return CustomPaint(
                size: size,
                painter: _GradientBgPainter(
                  progress: _bgController.value,
                  accent: _pages[_currentPage].accentColor,
                ),
              );
            },
          ),

          // Page content
          PageView.builder(
            controller: _pageController,
            itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              return _OnboardingPageView(
                page: _pages[index],
                isActive: index == _currentPage,
                pulseAnimation: _pulseController,
              );
            },
          ),

          // Top: Skip button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: TextButton(
              onPressed: _skip,
              child: Text(
                'Skip',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          // Bottom: indicators + next button
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomPadding + 24,
            child: Column(
              children: [
                // Page indicators
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_pages.length, (i) {
                    final isActive = i == _currentPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isActive ? 28 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isActive
                            ? _pages[_currentPage].accentColor
                            : Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 32),
                // Next / Get Started button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: FilledButton(
                        key: ValueKey(_currentPage == _pages.length - 1),
                        onPressed: _next,
                        style: FilledButton.styleFrom(
                          backgroundColor: _pages[_currentPage].accentColor,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        child: Text(
                          _currentPage == _pages.length - 1
                              ? "Let's Go"
                              : 'Next',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Single Page View ─────────────────────────────────────────────────────────

class _OnboardingPageView extends StatelessWidget {
  final OnboardingPage page;
  final bool isActive;
  final AnimationController pulseAnimation;

  const _OnboardingPageView({
    required this.page,
    required this.isActive,
    required this.pulseAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Padding(
      padding: EdgeInsets.fromLTRB(32, topPadding + 60, 32, 180),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Animated icon with glow
          AnimatedBuilder(
            animation: pulseAnimation,
            builder: (context, child) {
              final pulse = 0.9 + pulseAnimation.value * 0.1;
              return Transform.scale(
                scale: pulse,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: page.accentColor.withValues(alpha: 0.15),
                    boxShadow: [
                      BoxShadow(
                        color: page.accentColor.withValues(
                          alpha: 0.15 + pulseAnimation.value * 0.1,
                        ),
                        blurRadius: 30 + pulseAnimation.value * 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(page.icon, size: 36, color: page.accentColor),
                ),
              );
            },
          ),
          const SizedBox(height: 40),

          // Title
          Text(
            page.title,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.15,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),

          // Subtitle
          Text(
            page.subtitle,
            style: TextStyle(
              fontSize: 17,
              color: page.accentColor.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 36),

          // Feature bullets
          ...page.features.asMap().entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: page.accentColor.withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: page.accentColor,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withValues(alpha: 0.7),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Background Painter ───────────────────────────────────────────────────────

class _GradientBgPainter extends CustomPainter {
  final double progress;
  final Color accent;

  _GradientBgPainter({required this.progress, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    // Slow-moving gradient orbs
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);

    // Orb 1: accent color, top-right
    final x1 =
        size.width * 0.7 + math.sin(progress * math.pi * 2) * size.width * 0.15;
    final y1 =
        size.height * 0.2 +
        math.cos(progress * math.pi * 2) * size.height * 0.1;
    paint.color = accent.withValues(alpha: 0.08);
    canvas.drawCircle(Offset(x1, y1), size.width * 0.4, paint);

    // Orb 2: accent shifted, bottom-left
    final x2 =
        size.width * 0.3 +
        math.cos(progress * math.pi * 2 + 1) * size.width * 0.1;
    final y2 =
        size.height * 0.7 +
        math.sin(progress * math.pi * 2 + 1) * size.height * 0.08;
    paint.color = accent.withValues(alpha: 0.05);
    canvas.drawCircle(Offset(x2, y2), size.width * 0.35, paint);
  }

  @override
  bool shouldRepaint(covariant _GradientBgPainter old) =>
      old.progress != progress || old.accent != accent;
}
