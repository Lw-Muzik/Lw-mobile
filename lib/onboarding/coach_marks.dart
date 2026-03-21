import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single step in the walkthrough.
class CoachStep {
  final GlobalKey targetKey;
  final String title;
  final String description;
  final IconData icon;
  final TooltipPosition tooltipPosition;
  final VoidCallback? onShow;

  const CoachStep({
    required this.targetKey,
    required this.title,
    required this.description,
    required this.icon,
    this.tooltipPosition = TooltipPosition.below,
    this.onShow,
  });
}

enum TooltipPosition { above, below }

/// Launches a step-by-step coach mark walkthrough over the current screen.
/// Each instance uses its own [id] for persistence, so different screens
/// can have independent walkthroughs.
class CoachMarkController {
  final String id;
  OverlayEntry? _entry;
  int _currentStep = 0;
  late List<CoachStep> _steps;
  late BuildContext _context;
  VoidCallback? onComplete;

  CoachMarkController(this.id);

  String get _prefsKey => 'coach_shown_$id';

  Future<bool> hasBeenShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  Future<void> markShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }

  /// Reset all coach marks across the app.
  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('coach_shown_'));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// Start the walkthrough. Call after the UI has laid out.
  void start(BuildContext context, List<CoachStep> steps,
      {VoidCallback? onComplete}) {
    if (steps.isEmpty) return;
    _context = context;
    _steps = steps;
    _currentStep = 0;
    this.onComplete = onComplete;
    _showStep();
  }

  void _safeRemoveEntry() {
    if (_entry != null && _entry!.mounted) {
      _entry!.remove();
    }
    _entry = null;
  }

  void _showStep() {
    _safeRemoveEntry();

    if (_currentStep >= _steps.length) {
      markShown();
      onComplete?.call();
      return;
    }

    final step = _steps[_currentStep];
    step.onShow?.call();

    _showStepWithRetry(step, retries: 8);
  }

  void _showStepWithRetry(CoachStep step, {int retries = 8}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_currentStep >= _steps.length) return;

        final targetRect = _getTargetRect(step.targetKey);
        if (targetRect == null) {
          if (retries > 0) {
            Future.delayed(const Duration(milliseconds: 300), () {
              _showStepWithRetry(step, retries: retries - 1);
            });
          } else {
            _currentStep++;
            _showStep();
          }
          return;
        }

        _entry = OverlayEntry(
          builder: (_) => _CoachOverlay(
            targetRect: targetRect,
            step: step,
            stepIndex: _currentStep,
            totalSteps: _steps.length,
            onNext: _next,
            onSkip: _skip,
          ),
        );
        Overlay.of(_context).insert(_entry!);
      });
    });
  }

  Rect? _getTargetRect(GlobalKey key) {
    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return null;
    final position = renderBox.localToGlobal(Offset.zero);
    final rect = position & renderBox.size;
    // Verify the target is actually on screen
    if (rect.top < -50 || rect.bottom < 0) return null;
    return rect;
  }

  void _next() {
    _currentStep++;
    _showStep();
  }

  void _skip() {
    _safeRemoveEntry();
    markShown();
    onComplete?.call();
  }

  void dispose() {
    _safeRemoveEntry();
  }
}

// =============================================================================
// Coach overlay widget
// =============================================================================

class _CoachOverlay extends StatefulWidget {
  final Rect targetRect;
  final CoachStep step;
  final int stepIndex;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _CoachOverlay({
    required this.targetRect,
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.onNext,
    required this.onSkip,
  });

  @override
  State<_CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<_CoachOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final isLast = widget.stepIndex == widget.totalSteps - 1;

    final spotlight = widget.targetRect.inflate(8);

    // Decide tooltip position based on available space
    final spaceBelow = size.height - spotlight.bottom;
    final spaceAbove = spotlight.top;
    final showBelow = widget.step.tooltipPosition == TooltipPosition.below
        ? spaceBelow > 220
        : spaceAbove < 220;

    final tooltipTop = showBelow ? spotlight.bottom + 16 : null;
    final tooltipBottom = showBelow ? null : size.height - spotlight.top + 16;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Dark backdrop with spotlight cutout
            GestureDetector(
              onTap: widget.onNext,
              child: CustomPaint(
                size: size,
                painter: _SpotlightPainter(spotlight: spotlight),
              ),
            ),

            // Soft glow around target
            Positioned(
              left: spotlight.left - 12,
              top: spotlight.top - 12,
              child: IgnorePointer(
                child: Container(
                  width: spotlight.width + 24,
                  height: spotlight.height + 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      spotlight.shortestSide / 2 + 12,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD4A825).withValues(alpha: 0.35),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Tap target
            Positioned.fromRect(
              rect: spotlight,
              child: GestureDetector(
                onTap: widget.onNext,
                behavior: HitTestBehavior.translucent,
                child: const SizedBox.expand(),
              ),
            ),

            // Tooltip card
            Positioned(
              left: 24,
              right: 24,
              top: tooltipTop,
              bottom: tooltipBottom,
              child: ScaleTransition(
                scale: _scaleAnim,
                alignment:
                    showBelow ? Alignment.topCenter : Alignment.bottomCenter,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFD4A825).withValues(alpha: 0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFD4A825)
                                  .withValues(alpha: 0.15),
                            ),
                            child: Icon(widget.step.icon,
                                size: 18, color: const Color(0xFFD4A825)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.step.title,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${widget.stepIndex + 1}/${widget.totalSteps}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.5),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.step.description,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.65),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: widget.onSkip,
                            child: Text(
                              'Skip',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 14,
                              ),
                            ),
                          ),
                          FilledButton(
                            onPressed: widget.onNext,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFD4A825),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              isLast ? 'Got It' : 'Next',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Step dots
            Positioned(
              left: 0,
              right: 0,
              bottom: padding.bottom + 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.totalSteps, (i) {
                  final active = i == widget.stepIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFFD4A825)
                          : Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Spotlight painter
// =============================================================================

class _SpotlightPainter extends CustomPainter {
  final Rect spotlight;

  _SpotlightPainter({required this.spotlight});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.8);
    final fullPath = Path()..addRect(Offset.zero & size);
    final radius = spotlight.shortestSide / 2;
    final cutout = Path()
      ..addRRect(RRect.fromRectAndRadius(
        spotlight,
        Radius.circular(radius.clamp(8, 24)),
      ));
    final combined = Path.combine(PathOperation.difference, fullPath, cutout);
    canvas.drawPath(combined, paint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      old.spotlight != spotlight;
}
