import 'dart:math';
import 'package:flutter/material.dart';

/// Professional spectrum analyzer — bars fill the screen width,
/// height responds fully to amplitude, bass/mid/treble properly mapped.
class SpectrumVisualizer extends CustomPainter {
  final List<double> audioData;
  final double time;
  final Color color;

  static const int _barCount = 64;

  SpectrumVisualizer({
    required this.audioData,
    required this.time,
    this.color = Colors.blue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (audioData.isEmpty) return;

    final w = size.width;
    final h = size.height;
    final barW = w / _barCount;
    const gap = 1.5;

    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < _barCount; i++) {
      // Map bar index to audio data with logarithmic frequency scaling.
      // Lower bars = bass (fewer data points, wider range),
      // Higher bars = treble (more data points, narrower range).
      final t = i / _barCount;
      final logIdx = pow(t, 1.8) * audioData.length; // log curve favors bass
      final dataIdx = logIdx.floor().clamp(0, audioData.length - 1);

      // Average a small neighborhood for smoother look
      double amp = 0;
      int count = 0;
      final spread = max(1, (audioData.length / _barCount * 0.5).round());
      for (int j = -spread; j <= spread; j++) {
        final idx = (dataIdx + j).clamp(0, audioData.length - 1);
        amp += audioData[idx];
        count++;
      }
      amp = (amp / count).clamp(0.0, 1.0);

      // Boost: bass gets extra gain, treble gets slight boost
      final bassBoost = (1.0 - t) * 0.4; // 0.4 extra at bass, 0 at treble
      final boosted = (amp * (1.0 + bassBoost)).clamp(0.0, 1.0);

      // Subtle per-bar animation for liveliness
      final anim = 0.97 + 0.03 * sin(time * pi * 2 + i * 0.2);

      // Bar height uses 85% of screen height
      final barH = boosted * anim * h * 0.85;
      final x = i * barW + gap / 2;
      final bw = barW - gap;
      if (bw <= 0) continue;

      // Color: slightly brighter for louder bars
      paint.color = color.withValues(alpha: 0.5 + boosted * 0.5);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, h - barH, bw, barH),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SpectrumVisualizer oldDelegate) => true;
}
