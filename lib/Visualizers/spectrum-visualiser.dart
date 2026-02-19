import 'dart:math';
import 'package:flutter/material.dart';

class SpectrumVisualizer extends CustomPainter {
  final List<double> audioData;
  final double time;
  final Color color;

  SpectrumVisualizer({
    required this.audioData,
    required this.time,
    this.color = Colors.blue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (audioData.isEmpty) return;

    final width = size.width;
    final height = size.height;
    // Increase spacing between bars
    final barWidth = width / (audioData.length * 1.5);
    final spacing = barWidth * 1.5; // 50% of bar width for spacing
    final actualBarWidth = barWidth;

    // Single color paint
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (int i = 0; i < audioData.length / 8; i++) {
      // Add subtle animation to the bar heights
      final animatedValue =
          audioData[i] * (0.9 + 0.1 * sin(time * 2 + i * 0.2));

      // Limit height to 50% of screen height
      final barHeight = (height * 0.3) * animatedValue.clamp(0.0, 10);

      // Calculate bar position
      final x = i * 7; //(barWidth + spacing);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x.toDouble(),
          height - barHeight,
          5,
          barHeight,
        ),
        Radius.circular(actualBarWidth),
      );

      // Draw main bar
      canvas.drawRRect(rect, paint);

      // Add subtle shine effect
      final shinePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill;

      final shineRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x + spacing / 2,
          height - barHeight - 1,
          actualBarWidth,
          actualBarWidth * 0.5,
        ),
        Radius.circular(actualBarWidth / 2),
      );

      // canvas.drawRRect(shineRect, shinePaint);
    }

    // Draw fewer reference lines
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Only draw two reference lines at 25% and 50% height
    for (int i = 1; i <= 2; i++) {
      final y = height * (i / 4);
      // canvas.drawLine(
      //   Offset(0, y),
      //   Offset(width, y),
      //   linePaint,
      // );
    }
  }

  @override
  bool shouldRepaint(covariant SpectrumVisualizer oldDelegate) {
    return oldDelegate.time != time || oldDelegate.audioData != audioData;
  }
}
