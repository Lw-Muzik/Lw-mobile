import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single step in the walkthrough.
class CoachStep {
  /// Key of the widget to spotlight.
  final GlobalKey targetKey;

  /// Instruction text (e.g. "Tap here to search for songs").
  final String title;
  final String description;

  /// Icon shown in the tooltip.
  final IconData icon;

  /// Where to position the tooltip relative to the target.
  final TooltipPosition tooltipPosition;

  /// Optional callback fired when this step is shown (e.g. to switch tabs).
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

/// Persistence key for tracking whether the walkthrough has been shown.
const _prefsKey = 'coach_walkthrough_shown';

/// Launches a step-by-step coach mark walkthrough over the current screen.
/// Each step spotlights a widget (via its GlobalKey) and shows instructions.
/// Tapping the spotlight area or "Next" advances to the next step.
class CoachMarkController {
  OverlayEntry? _entry;
  int _currentStep = 0;
  late List<CoachStep> _steps;
  late BuildContext _context;
  VoidCallback? onComplete;

  /// Whether the walkthrough has already been shown.
  static Future<bool> hasBeenShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  /// Mark as shown.
  static Future<void> markShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }

  /// Reset so it shows again.
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// Start the walkthrough. Call after the UI has laid out (e.g. post-frame).
  void start(BuildContext context, List<CoachStep> steps,
      {VoidCallback? onComplete}) {
    if (steps.isEmpty) return;
    _context = context;
    _steps = steps;
    _currentStep = 0;
    this.onComplete = onComplete;
    _showStep();
  }

  void _showStep() {
    _entry?.remove();

    if (_currentStep >= _steps.length) {
      markShown();
      onComplete?.call();
      return;
    }

    final step = _steps[_currentStep];
    step.onShow?.call();

    // Wait two frames for layout changes from onShow to settle, then retry
    _showStepWithRetry(step, retries: 5);
  }

  void _showStepWithRetry(CoachStep step, {int retries = 5}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_currentStep >= _steps.length) return;

        final targetRect = _getTargetRect(step.targetKey);
        if (targetRect == null) {
          if (retries > 0) {
            // Target not visible yet — retry after a short delay
            Future.delayed(const Duration(milliseconds: 300), () {
              _showStepWithRetry(step, retries: retries - 1);
            });
          } else {
            // Give up on this step after all retries
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
    return position & renderBox.size;
  }

  void _next() {
    _currentStep++;
    _showStep();
  }

  void _skip() {
    _entry?.remove();
    _entry = null;
    markShown();
    onComplete?.call();
  }

  void dispose() {
    _entry?.remove();
    _entry = null;
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

    // Expand target rect slightly for the spotlight
    final spotlight = widget.targetRect.inflate(8);

    // Tooltip positioning
    final bool showBelow =
        widget.step.tooltipPosition == TooltipPosition.below ||
            (widget.step.tooltipPosition == TooltipPosition.above &&
                spotlight.top < 120);

    final tooltipTop = showBelow ? spotlight.bottom + 20 : null;
    final tooltipBottom =
        showBelow ? null : size.height - spotlight.top + 20;

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
                painter: _SpotlightPainter(
                  spotlight: spotlight,
                  opacity: _fadeAnim.value,
                ),
              ),
            ),

            // Pulsing ring around target
            Positioned(
              left: spotlight.left - 4,
              top: spotlight.top - 4,
              child: IgnorePointer(
                child: Container(
                  width: spotlight.width + 8,
                  height: spotlight.height + 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      spotlight.shortestSide / 2 + 4,
                    ),
                    border: Border.all(
                      color: const Color(0xFFD4A825).withValues(alpha: 0.6),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),

            // Tap target — advances to next step
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
                alignment: showBelow
                    ? Alignment.topCenter
                    : Alignment.bottomCenter,
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
                          // Step counter
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
                              'Skip All',
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
                              isLast ? 'Done' : 'Next',
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
// Spotlight painter — dark backdrop with rounded-rect cutout
// =============================================================================

class _SpotlightPainter extends CustomPainter {
  final Rect spotlight;
  final double opacity;

  _SpotlightPainter({required this.spotlight, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.8 * opacity);

    // Full screen path
    final fullPath = Path()..addRect(Offset.zero & size);

    // Cutout with rounded corners
    final radius = spotlight.shortestSide / 2;
    final cutout = Path()
      ..addRRect(RRect.fromRectAndRadius(
        spotlight,
        Radius.circular(radius.clamp(8, 24)),
      ));

    // Combine: full screen minus cutout
    final combined = Path.combine(PathOperation.difference, fullPath, cutout);
    canvas.drawPath(combined, paint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      old.spotlight != spotlight || old.opacity != opacity;
}
