import 'package:flutter/material.dart';

class AppThemes {
  static ThemeData lightTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color.fromARGB(255, 156, 15, 5),
        brightness: Brightness.light,
        background: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.white
      // searchViewTheme: const SearchViewThemeData(elevation: 0,ba: Color.fromARGB(255, 156, 15, 5))
      );
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color.fromARGB(255, 156, 15, 5),
      brightness: Brightness.dark,
      background: Colors.black,
    ),
    scaffoldBackgroundColor: Colors.black,
  );
  static ThemeData fancyTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color.fromARGB(255, 156, 15, 5),
      brightness: Brightness.dark,
      background: Colors.black,
    ),
  );
}
