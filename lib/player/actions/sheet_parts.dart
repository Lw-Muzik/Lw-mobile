/// The pieces every page of the song actions sheet is built from.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../themes/ember.dart';
import 'motion.dart';

/// White at [alpha] — the sheet draws in light on glass, not in greys.
Color glassWhite(double alpha) => Colors.white.withValues(alpha: alpha);

/// One of the big buttons along the top: an icon over a word.
class QuickAction extends StatefulWidget {
  const QuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.background,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// Lit in the accent: the action is done (downloaded) or on.
  final bool active;

  /// Drawn behind the icon and label, inside the button — the download's
  /// liquid.
  final Widget? background;

  @override
  State<QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<QuickAction> {
  bool _down = false;

  void _press(bool down) {
    if (widget.onTap == null) return;
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? Ember.accent : Ember.textPrimary;
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapCancel: () => _press(false),
        onTapUp: (_) => _press(false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: _down ? 0.93 : 1,
          duration: const Duration(milliseconds: 140),
          curve: _down ? Curves.easeOut : const SpringCurve(dampingRatio: 0.5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 80,
            decoration: BoxDecoration(
              color: glassWhite(_down ? 0.13 : 0.075),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: widget.active
                    ? Ember.accent.withValues(alpha: 0.35)
                    : glassWhite(0.07),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ?widget.background,
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(
                              scale: CurvedAnimation(
                                parent: animation,
                                curve: const SpringCurve(dampingRatio: 0.45),
                              ),
                              child: child,
                            ),
                        child: Icon(
                          widget.icon,
                          key: ValueKey(widget.icon),
                          color: color,
                          size: 25,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: widget.active
                                ? Ember.accent
                                : glassWhite(0.86),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
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
      ),
    );
  }
}

/// A rounded group of rows, hairlines between them.
class ActionGroup extends StatelessWidget {
  const ActionGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      decoration: BoxDecoration(
        color: glassWhite(0.045),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: glassWhite(0.06)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 66),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: glassWhite(0.06),
                  ),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// One row: an icon in a soft disc, what it does, and where it goes.
class ActionRow extends StatelessWidget {
  const ActionRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.busy = false,
    this.chevron = true,
    this.leading,
    this.trailing,
  });

  final IconData icon;
  final String title;

  /// What or where — the album's name, the artists — so the row says where
  /// it goes before it is tapped.
  final String? subtitle;
  final VoidCallback? onTap;

  /// Working on it (finding the album): a small spinner instead of the
  /// chevron, and taps wait.
  final bool busy;
  final bool chevron;

  /// Replaces the icon disc (a playlist's cover, an artist's initial).
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onTap!();
              }
            : null,
        splashColor: glassWhite(0.06),
        highlightColor: glassWhite(0.05),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 62),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: [
                leading ??
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: glassWhite(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 20, color: glassWhite(0.9)),
                    ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Ember.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: Text(
                            subtitle!,
                            key: ValueKey(subtitle),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: glassWhite(0.55),
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (busy)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: glassWhite(0.6),
                    ),
                  )
                else if (trailing != null)
                  trailing!
                else if (chevron)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: glassWhite(0.32),
                    size: 22,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The top of a page deeper in the sheet: back, and what the page is.
class SheetPageHeader extends StatelessWidget {
  const SheetPageHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.trailing,
  });

  final String title;
  final VoidCallback onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 14, 12),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Back',
            child: InkResponse(
              onTap: () {
                HapticFeedback.selectionClick();
                onBack();
              },
              radius: 24,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: glassWhite(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 17,
                  color: glassWhite(0.9),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Ember.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A small pill naming where the song comes from.
class SourceChip extends StatelessWidget {
  const SourceChip({
    super.key,
    required this.icon,
    required this.label,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
      decoration: BoxDecoration(
        color: glassWhite(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: glassWhite(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor ?? glassWhite(0.75)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: glassWhite(0.75),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
