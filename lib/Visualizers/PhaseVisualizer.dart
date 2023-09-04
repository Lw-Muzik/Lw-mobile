import 'dart:math';

import 'package:flutter/material.dart';

class PhaseVisualiser extends CustomPainter {
  final List<int> waveData;
  final double height;
  final double width;
  final Color color;
  final int density;
  const PhaseVisualiser(
      {required this.waveData,
      required this.height,
      this.density = 50,
      required this.width,
      this.color = Colors.red});
  @override
  void paint(Canvas canvas, Size size) {
    // phase calculations

    List<int> fft = waveData; // Initialize your FFT array here

    List<double> magnitudes = List<double>.filled((density ~/ 2) + 1, 0);
    List<double> phases = List<double>.filled((density ~/ 2) + 1, 0.0);
    print(waveData);
    magnitudes[0] = fft[0].abs().toDouble(); // DC
    magnitudes[(density ~/ 2)] = fft[1].abs().toDouble(); // Nyquist
    phases[0] = phases[(density ~/ 2)] = 0.0;

    for (int k = 1; k < (density ~/ 2); k++) {
      int i = k * 2;
      magnitudes[k] = sqrt(fft[i] * fft[i] + fft[i + 1] * fft[i + 1]);
      phases[k] = atan2(fft[i + 1], fft[i]);
    }

    // Print or use the magnitudes and phases as needed
    print("Magnitudes: $magnitudes");
    print("Phases: $phases");
  }

  @override
  bool shouldRepaint(oldDelegate) => true;

  @override
  bool shouldRebuildSemantics(oldDelegate) => true;
}
