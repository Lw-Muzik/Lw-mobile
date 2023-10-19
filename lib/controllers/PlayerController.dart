import 'package:flutter/material.dart';


class PlayerController extends ChangeNotifier {
  // the tracks loaded
  String _text = "";
  String get text => _text;
  set text(String x) {
    _text = x;
    notifyListeners();
  }

// the text header
  String _textHeader = '';
  String get textHeader => _textHeader;
  set textHeader(String x) {
    _textHeader = x;
    notifyListeners();
  }
}
