import 'dart:math';
import 'package:flutter/material.dart';

/// Professional spectrum analyzer — reads pre-processed frequency bands
/// from WaveVisualizer's _freqBands (already log-mapped, normalized, bass-boosted).
class SpectrumVisualizer extends CustomPainter {
  final List<double> audioData; // pre-processed freq bands, 0..1
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
      // Read directly from pre-processed bands (already log-freq mapped)
      final dataIdx = (i * audioData.length / _barCount).floor()
          .clamp(0, audioData.length - 1);
      final amp = audioData[dataIdx].clamp(0.0, 1.0);

      // Subtle per-bar animation
      final anim = 0.97 + 0.03 * sin(time * pi * 2 + i * 0.2);

      // Bar height uses 90% of screen height
      final barH = amp * anim * h * 0.9;
      final x = i * barW + gap / 2;
      final bw = barW - gap;
      if (bw <= 0) continue;

      paint.color = color.withValues(alpha: 0.45 + amp * 0.55);

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
