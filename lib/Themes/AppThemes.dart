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
/// # `primary` is the readable red, not the brand red
///
/// `#9C0F05` measures **2.28:1** on this ground — below the 3:1 floor for UI
/// components. `colorScheme.primary` is what widgets use to *draw* things, so
/// it gets [Ember.ember400] at 5.18:1. The brand red stays a fill, where white
/// on it measures 8.45:1, and is available as [Ember.ember600] for anything
/// that wants a filled surface.
class AppThemes {
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Ember.ember600,
      brightness: Brightness.light,
      surface: Colors.white,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
    ),
    scaffoldBackgroundColor: Colors.white,
  );

  static final ColorScheme _emberDark = ColorScheme.fromSeed(
    seedColor: Ember.ember600,
    brightness: Brightness.dark,
    surface: Ember.ground,
  ).copyWith(
    // Drawn with, so it must be legible rather than on-brand.
    primary: Ember.ember400,
    onPrimary: Colors.white,
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
