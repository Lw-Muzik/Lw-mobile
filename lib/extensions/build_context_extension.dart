import '/exports/exports.dart';

extension BuildContextExtension on BuildContext {
  // add the necessary extensions like color, theme
  Color get primaryColor => Theme.of(this).primaryColor;

  // media query
  double get width => MediaQuery.of(this).size.width;
  double get height => MediaQuery.of(this).size.height;
}
