import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/app_controller.dart';

class ModeChooser extends StatefulWidget {
  final void Function(AppMode mode) onComplete;
  const ModeChooser({super.key, required this.onComplete});

  @override
  State<ModeChooser> createState() => _ModeChooserState();
}

class _ModeChooserState extends State<ModeChooser>
    with TickerProviderStateMixin {
  AppMode? _selected;
  late final AnimationController _bgController;
  late final AnimationController _pulseController;
  late final AnimationController _entryController;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarBrightness: Brightness.dark),
    );
  }

  @override
  void dispose() {
    _bgController.dispose();
    _pulseController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  void _continue() {
    if (_selected == null) return;
    widget.onComplete(_selected!);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(
        children: [
          // Animated background
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, _) {
              return CustomPaint(
                size: size,
                painter: _BgPainter(
                  progress: _bgController.value,
                  accent: _selected == AppMode.equalizer
                      ? const Color(0xFF5EC4D4)
                      : const Color(0xFFD4A825),
                ),
              );
            },
          ),

          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: topPadding * 0.3 + 24),

                  // Title
                  FadeTransition(
                    opacity: CurvedAnimation(
                      parent: _entryController,
                      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
                    ),
                    child: SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(0, 0.3),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: _entryController,
                              curve: const Interval(
                                0.0,
                                0.5,
                                curve: Curves.easeOut,
                              ),
                            ),
                          ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'How would you\nlike to use Hype?',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.15,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'You can change this anytime',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.white.withValues(alpha: 0.45),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(flex: 1),

                  // Cards
                  FadeTransition(
                    opacity: CurvedAnimation(
                      parent: _entryController,
                      curve: const Interval(0.3, 0.8, curve: Curves.easeOut),
                    ),
                    child: SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(0, 0.2),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: _entryController,
                              curve: const Interval(
                                0.3,
                                0.8,
                                curve: Curves.easeOut,
                              ),
                            ),
                          ),
                      child: Column(
                        children: [
                          _ModeCard(
                            icon: Icons.headphones_rounded,
                            title: 'Music Player',
                            subtitle: 'Full music experience with EQ',
                            accent: const Color(0xFFD4A825),
                            features: const [
                              'Play local, cloud & streaming music',
                              'Professional equalizer & effects',
                              'Visualizations, lyrics & more',
                            ],
                            selected: _selected == AppMode.musicPlayer,
                            pulseAnimation: _pulseController,
                            onTap: () =>
                                setState(() => _selected = AppMode.musicPlayer),
                          ),
                          const SizedBox(height: 16),
                          if (Platform.isAndroid)
                            _ModeCard(
                              icon: Icons.equalizer_rounded,
                              title: 'Equalizer',
                              subtitle: 'System-wide audio enhancement',
                              accent: const Color(0xFF5EC4D4),
                              features: const [
                                '32-band graphic & parametric EQ',
                                'Apply to Spotify, YouTube & all apps',
                                'Tone controls, compressor & limiter',
                              ],
                              selected: _selected == AppMode.equalizer,
                              pulseAnimation: _pulseController,
                              onTap: () =>
                                  setState(() => _selected = AppMode.equalizer),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(flex: 2),

                  // Continue button
                  FadeTransition(
                    opacity: CurvedAnimation(
                      parent: _entryController,
                      curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(bottom: bottomPadding + 24),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: FilledButton(
                            key: ValueKey(_selected),
                            onPressed: _selected != null ? _continue : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: _selected == AppMode.equalizer
                                  ? const Color(0xFF5EC4D4)
                                  : const Color(0xFFD4A825),
                              foregroundColor: Colors.black,
                              disabledBackgroundColor: Colors.white.withValues(
                                alpha: 0.08,
                              ),
                              disabledForegroundColor: Colors.white.withValues(
                                alpha: 0.25,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                            child: const Text('Continue'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mode Card ───────────────────────────────────────────────────────────────

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final List<String> features;
  final bool selected;
  final AnimationController pulseAnimation;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.features,
    required this.selected,
    required this.pulseAnimation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.06),
            width: selected ? 1.5 : 1,
          ),
          color: selected
              ? accent.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.03),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.15),
                    blurRadius: 30,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Icon with glow
            AnimatedBuilder(
              animation: pulseAnimation,
              builder: (context, child) {
                final glowAlpha = selected
                    ? 0.12 + pulseAnimation.value * 0.08
                    : 0.06;
                return Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: selected ? 0.15 : 0.08),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: accent.withValues(alpha: glowAlpha),
                              blurRadius: 20 + pulseAnimation.value * 10,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    icon,
                    size: 26,
                    color: selected ? accent : accent.withValues(alpha: 0.6),
                  ),
                );
              },
            ),
            const SizedBox(width: 18),

            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.8),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: selected
                          ? accent.withValues(alpha: 0.8)
                          : Colors.white.withValues(alpha: 0.35),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...features.map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selected
                                  ? accent.withValues(alpha: 0.6)
                                  : Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              f,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(
                                  alpha: selected ? 0.55 : 0.3,
                                ),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Selection indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? accent
                      : Colors.white.withValues(alpha: 0.15),
                  width: selected ? 2 : 1.5,
                ),
                color: selected ? accent : Colors.transparent,
              ),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.black,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Background Painter ──────────────────────────────────────────────────────

class _BgPainter extends CustomPainter {
  final double progress;
  final Color accent;

  _BgPainter({required this.progress, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);

    final x1 =
        size.width * 0.7 + math.sin(progress * math.pi * 2) * size.width * 0.15;
    final y1 =
        size.height * 0.3 +
        math.cos(progress * math.pi * 2) * size.height * 0.1;
    paint.color = accent.withValues(alpha: 0.06);
    canvas.drawCircle(Offset(x1, y1), size.width * 0.4, paint);

    final x2 =
        size.width * 0.3 +
        math.cos(progress * math.pi * 2 + 1) * size.width * 0.1;
    final y2 =
        size.height * 0.7 +
        math.sin(progress * math.pi * 2 + 1) * size.height * 0.08;
    paint.color = accent.withValues(alpha: 0.04);
    canvas.drawCircle(Offset(x2, y2), size.width * 0.35, paint);
  }

  @override
  bool shouldRepaint(covariant _BgPainter old) =>
      old.progress != progress || old.accent != accent;
}
