import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight feature discovery system.
/// Shows a tooltip-style hint the first time a user encounters a feature.
/// Persists shown state in SharedPreferences.
class FeatureHints {
  static const _prefix = 'hint_shown_';

  static Future<bool> shouldShow(String featureId) async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('$_prefix$featureId') ?? false);
  }

  static Future<void> markShown(String featureId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$featureId', true);
  }

  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}

/// Shows a brief tooltip hint the first time a user sees a feature.
/// No persistent dots — just a one-time auto-dismissing tooltip.
/// Use [delay] to stagger multiple hints on the same screen.
class FeatureHintBadge extends StatefulWidget {
  final String featureId;
  final String hint;
  final Widget child;
  final Duration delay;

  const FeatureHintBadge({
    super.key,
    required this.featureId,
    required this.hint,
    required this.child,
    this.delay = Duration.zero,
  });

  @override
  State<FeatureHintBadge> createState() => _FeatureHintBadgeState();
}

class _FeatureHintBadgeState extends State<FeatureHintBadge> {
  bool _hintShown = false;

  @override
  void initState() {
    super.initState();
    // Auto-show tooltip after a short delay on first encounter, then never again
    _autoShowHint();
  }

  Future<void> _autoShowHint() async {
    final should = await FeatureHints.shouldShow(widget.featureId);
    if (!should || !mounted) return;

    // Wait for layout + stagger delay
    await Future.delayed(Duration(milliseconds: 800 + widget.delay.inMilliseconds));
    if (!mounted || _hintShown) return;

    _hintShown = true;
    FeatureHints.markShown(widget.featureId);
    _showHintTooltip(context);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  void _showHintTooltip(BuildContext context) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => _HintTooltipOverlay(
        hint: widget.hint,
        onDismiss: () { if (entry.mounted) entry.remove(); },
      ),
    );

    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () {
      if (entry.mounted) entry.remove();
    });
  }
}

class _HintTooltipOverlay extends StatefulWidget {
  final String hint;
  final VoidCallback onDismiss;

  const _HintTooltipOverlay({required this.hint, required this.onDismiss});

  @override
  State<_HintTooltipOverlay> createState() => _HintTooltipOverlayState();
}

class _HintTooltipOverlayState extends State<_HintTooltipOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onDismiss,
      behavior: HitTestBehavior.translucent,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 100,
            left: 24,
            right: 24,
          ),
          child: FadeTransition(
            opacity: _fadeIn,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFD4A825).withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lightbulb_rounded,
                      color: Color(0xFFD4A825), size: 20),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      widget.hint,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
