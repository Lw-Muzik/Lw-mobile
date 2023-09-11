import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../Themes/AppThemes.dart';

class ThemeController extends Cubit<ThemeData> {
  ThemeController() : super(theme);
  static ThemeData theme = AppThemes.lightTheme;
  void setTheme(int theme) {
    switch (theme) {
      case 1:
        emit(AppThemes.lightTheme);
        break;
      case 2:
        emit(AppThemes.darkTheme);
        break;
      case 3:
        emit(AppThemes.fancyTheme);
        break;
    }
  }
}
