import 'package:eq_app/Global/index.dart';
import 'package:flutter/material.dart';

class AppThemes {
  static ThemeData lightTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color.fromARGB(255, 156, 15, 5),
        brightness: Brightness.light,
        background: Colors.white,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
      ),
      scaffoldBackgroundColor: Colors.white
      // searchViewTheme: const SearchViewThemeData(elevation: 0,ba: Color.fromARGB(255, 156, 15, 5))
      );
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
    ),
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color.fromARGB(255, 156, 15, 5),
      brightness: Brightness.dark,
      background: Colors.black,
    ),
    scaffoldBackgroundColor: Colors.black,
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
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color.fromARGB(255, 156, 15, 5),
      brightness: Brightness.dark,
      background: Colors.black,
    ),
  );
}
