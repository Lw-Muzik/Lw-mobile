/// "Ember" — the surfaces outside the player.
///
/// Dark-first, editorial, artwork-led. Applies to Home, Library and Settings.
/// The player is deliberately untouched.
///
/// # One colour, taken from the logo
///
/// The mark is a gold spiral around a green note. The palette used to be red,
/// which appeared nowhere in it. [accent] is the spiral's own `#FFC107`.
///
/// Gold rather than the green because it is the dominant half of the mark and
/// the stronger colour here: **11.87:1** on this ground against the green's
/// 7.16:1.
///
/// Being that light inverts the usual dark-theme rule. Gold is superb to
/// *read* — an icon, a label, a border — but as a **solid fill it must carry
/// dark content**: white on it is 1.63:1, while the ground on it is 11.87:1.
/// So solid gold is reserved for small elements that carry no text, and
/// anything pill-shaped uses [accentWash] with gold content on top.
///
/// (sRGB relative luminance per WCAG 2.1, computed rather than eyeballed.)
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

  /// The one accent: the logo spiral's gold. 11.87:1 on [ground].
  ///
  /// Safe for anything that must be read, and for solid fills that carry no
  /// text (a knob, a bar, a 2px rule). For a filled *pill*, use [accentWash].
  static const accent = Color(0xFFFFC107);

  /// A tinted plate for filled pills, so gold content stays legible on it.
  ///
  /// Solid gold would need near-black content; every other selected state in
  /// the app is gold-on-dark, and one inverted pill in the middle of that
  /// reads as a different control rather than the same one, selected.
  static Color get accentWash => accent.withValues(alpha: 0.16);

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
