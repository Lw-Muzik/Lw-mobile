/// "Ember" — the surfaces outside the player.
///
/// Dark-first, editorial, artwork-led. Applies to Home, Library and Settings.
/// The player is deliberately untouched.
///
/// # Two reds, and why
///
/// The app's brand colour is `#9C0F05`. Measured against this palette's ground
/// it is **2.28:1** — below the 3:1 floor for UI components and nowhere near
/// the 4.5:1 floor for text. So it is a **fill** colour and only ever a fill:
/// white on it is 8.45:1, which is comfortable. Anything that has to be *read*
/// — an icon, a label, a border — uses [ember400] at **5.18:1**.
///
/// One token would have forced a choice between an unreadable accent and
/// abandoning the brand colour. Two tokens keep both.
///
/// (Figures are sRGB relative luminance per WCAG 2.1, computed rather than
/// eyeballed.)
///
/// # No live blur
///
/// `BackdropFilter` re-reads whatever is painted behind it and cannot be
/// raster-cached, so it recomputes on **every frame the app produces**. That was
/// this app's heat problem, and it was fixed by moving to `ImageFiltered`
/// wherever the content behind was static.
///
/// Chrome docked over a scrolling list is the pathological case for it: the
/// content behind genuinely changes, for the entire duration of every scroll. So
/// the nav bar and the mini player here are **opaque**, and depth comes from
/// layered surfaces and shadow instead.
library;

import 'package:flutter/material.dart';

class Ember {
  const Ember._();

  // --- Ground and surfaces -------------------------------------------------

  /// App background. Not pure black: black flattens depth, and on OLED it
  /// smears visibly when a list scrolls over it.
  static const ground = Color(0xFF0E0E10);
  static const surface = Color(0xFF17171A);
  static const surfaceHigh = Color(0xFF202024);
  static const outline = Color(0xFF2C2C32);

  // --- Text ----------------------------------------------------------------

  static const textPrimary = Color(0xFFF5F5F7);
  static Color get textSecondary => textPrimary.withValues(alpha: 0.62);
  static Color get textTertiary => textPrimary.withValues(alpha: 0.38);

  // --- Brand ---------------------------------------------------------------

  /// Fills only — filled buttons, the active nav pill. White text on it.
  static const ember600 = Color(0xFF9C0F05);

  /// Everything that has to be read on a dark ground: icons, labels, borders.
  static const ember400 = Color(0xFFE8503A);

  // --- Shape and rhythm ----------------------------------------------------

  static const radiusCard = 24.0;
  static const radiusTile = 16.0;
  static const radiusControl = 12.0;

  /// 8pt scale. 4 only inside a component.
  static const gutter = 20.0;
  static const shelfGap = 28.0;

  /// Soft, wide and low-opacity — depth without a drop-shadow look.
  static List<BoxShadow> get lift => const [
        BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8)),
      ];

  // --- Mix card colouring --------------------------------------------------

  /// A stable colour for a mix, derived from its name.
  ///
  /// Deliberately **not** extracted from artwork. Extraction means decoding
  /// images to sample them, it changes as artwork loads (so a card flickers
  /// into its own identity), and a mix has no single cover to extract from
  /// anyway. Deriving from the name gives each mix a colour that is its own,
  /// identical on every rebuild, and free.
  static Color accentFor(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    // Saturation and lightness are fixed so every mix sits at the same weight
    // against the ground; only hue moves.
    return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.42, 0.34).toColor();
  }

  /// The header style shelves use: small, wide-tracked, quiet.
  static TextStyle shelfTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall?.copyWith(
            color: textPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ) ??
      const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.1);
}
