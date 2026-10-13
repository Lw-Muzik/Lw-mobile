import 'package:flutter/material.dart';

/// The app's two typefaces, mirroring the Hype web app
/// (`--font-body` / `--font-display` in `hypemuzik-web/src/app.css`).
///
/// * **Satoshi** (400 / 500 / 700) is the default for every `Text`, wired in
///   through `ThemeData.fontFamily`, so nothing needs to name it.
/// * **Clash Display** (500 / 600 only) is for titles: page and app-bar titles,
///   the Home greeting, the full-player track title, artwork headings.
///
/// Clash Display ships no 400 or 700. Flutter would pick the nearest declared
/// weight on its own; [displayStyle] and [displayTextTheme] spell the weight out
/// so the choice is intentional. Use [medium] for section-sized headings and
/// [semibold] (the default) for page titles, as the web does.
///
/// The font files and their licence live in `assets/fonts/`.
abstract final class AppFonts {
  /// Family name declared in `pubspec.yaml`.
  static const String body = 'Satoshi';

  /// Family name declared in `pubspec.yaml`.
  static const String display = 'ClashDisplay';

  /// Clash Display Medium, the lighter of the two shipped weights.
  static const FontWeight medium = FontWeight.w500;

  /// Clash Display Semibold, the heavier of the two shipped weights.
  static const FontWeight semibold = FontWeight.w600;

  /// Clash Display's word space is too tight at display sizes ("Hype Muzik"
  /// reads "HypeMuzik"), so display styles add this fraction of the font size
  /// on top of it.
  static const double wordSpacingFactor = 0.25;

  /// The extra word spacing, in logical pixels, for a display style of
  /// [fontSize].
  static double wordSpacingFor(double fontSize) => fontSize * wordSpacingFactor;

  /// A Clash Display [TextStyle] for hand-styled titles. Given a [fontSize] it
  /// also carries the matching word spacing.
  ///
  /// [weight] must be [medium] or [semibold]; anything else is a bug because
  /// the family has no such face.
  static TextStyle displayStyle({
    double? fontSize,
    FontWeight weight = semibold,
    Color? color,
    double? height,
    double? letterSpacing,
    List<Shadow>? shadows,
  }) {
    assert(
      weight == medium || weight == semibold,
      'Clash Display only ships w500 and w600',
    );
    return TextStyle(
      fontFamily: display,
      fontWeight: weight,
      fontSize: fontSize,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      wordSpacing: fontSize == null ? null : wordSpacingFor(fontSize),
      shadows: shadows,
    );
  }

  /// Overrides to merge into a theme's `textTheme`: Clash Display on the
  /// display, headline and large-title roles. Only the family, weight and word
  /// spacing (for Material's default size of each role) are set; size, colour and height still come from Material's defaults.
  ///
  /// `titleLarge` is the app-bar and dialog title role (it is not used for
  /// list rows, those use `titleMedium` / `bodyLarge`), so it takes the
  /// lighter weight like the web's section titles.
  static final TextTheme displayTextTheme = TextTheme(
    displayLarge: TextStyle(fontFamily: display, fontWeight: semibold, wordSpacing: 57 * wordSpacingFactor),
    displayMedium: TextStyle(fontFamily: display, fontWeight: semibold, wordSpacing: 45 * wordSpacingFactor),
    displaySmall: TextStyle(fontFamily: display, fontWeight: semibold, wordSpacing: 36 * wordSpacingFactor),
    headlineLarge: TextStyle(fontFamily: display, fontWeight: semibold, wordSpacing: 32 * wordSpacingFactor),
    headlineMedium: TextStyle(fontFamily: display, fontWeight: semibold, wordSpacing: 28 * wordSpacingFactor),
    headlineSmall: TextStyle(fontFamily: display, fontWeight: semibold, wordSpacing: 24 * wordSpacingFactor),
    titleLarge: TextStyle(fontFamily: display, fontWeight: medium, wordSpacing: 22 * wordSpacingFactor),
  );

  /// Time and progress readouts: equal-width digits so the text does not
  /// jitter as it ticks.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];
}
