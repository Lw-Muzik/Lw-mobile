import 'package:flutter/services.dart';

class DSPSpeaker {
  final int id;
  final String name;
  final List<dynamic> freq;
  final List<double> gain;
  DSPSpeaker({
    required this.id,
    required this.freq,
    required this.gain,
    required this.name,
  });
  static List<dynamic> d = [];
  static Future<String> loadSpksFromAssets() async {
    return await rootBundle.loadString("assets/autoeq.json");
  }
}
