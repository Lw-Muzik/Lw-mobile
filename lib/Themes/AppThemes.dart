import 'package:eq_app/Global/index.dart';
import 'package:flutter/material.dart';

import '../themes/ember.dart';

/// The app's themes, carrying the Ember palette.
///
/// # Why the palette arrives through the theme
///
/// The browsing widgets — `LibraryListRow`, `SongTile`, the grid cards, the
/// sort button — already read `Theme.of(context).colorScheme`. Hardcoding Ember
/// into each of them would mean nine files agreeing about a colour, which is
/// nine chances to disagree later. Handing the palette to the theme means they
/// pick it up and cannot drift.
///
/// # `onPrimary` is dark, because the accent is light
///
/// [Ember.accent] is the logo's gold, 11.87:1 on this ground, so it is what
/// widgets draw with. It is light enough that Material's usual white-on-primary
/// would measure **1.63:1** — so `onPrimary` is the ground itself, at 11.87:1.
/// Every filled switch, slider thumb and button in the app rests on that one
/// line being right.
class AppThemes {
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Ember.accent,
      brightness: Brightness.light,
      surface: Colors.white,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
    ),
    scaffoldBackgroundColor: Colors.white,
  );

  static final ColorScheme _emberDark = ColorScheme.fromSeed(
    seedColor: Ember.accent,
    brightness: Brightness.dark,
    surface: Ember.ground,
  ).copyWith(
    // Drawn with, so it must be legible rather than on-brand.
    primary: Ember.accent,
    onPrimary: Ember.ground,
    surface: Ember.ground,
    onSurface: Ember.textPrimary,
    // Raised surfaces: cards, sheets, the selected segment.
    surfaceContainerHighest: Ember.surfaceHigh,
    outline: Ember.outline,
    outlineVariant: Ember.outline,
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
    ),
    colorScheme: _emberDark,
    scaffoldBackgroundColor: Ember.ground,
    splashFactory: InkSparkle.splashFactory,
  );

  static ThemeData fancyTheme = ThemeData(
    useMaterial3: true,
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      systemOverlayStyle: overlay,
      elevation: 0,
    ),
    // Fancy mode paints artwork behind everything, so the scaffold stays
    // transparent — but the roles still have to be the Ember ones or a card
    // drawn over the artwork reverts to Material's defaults.
    colorScheme: _emberDark,
    splashFactory: InkSparkle.splashFactory,
  );
}
