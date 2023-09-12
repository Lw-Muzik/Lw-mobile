// ignore_for_file: non_constant_identifier_names

import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/services.dart';

class DSPSpeaker {
  int id;
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
