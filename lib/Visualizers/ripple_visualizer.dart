import 'dart:math';
import 'package:flutter/material.dart';

class RippleVisualizer extends CustomPainter {
  final List<double> audioData;
  final double time;
  final Color color;

  RippleVisualizer({
    required this.audioData,
    required this.time,
    this.color = Colors.blue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    const numRipples = 8;
    const numPoints = 180;
    final maxRadius = min(size.width, size.height) / 2.5;

    if (audioData.isEmpty) return;

    final avgAmplitude = audioData.reduce((a, b) => a + b) / audioData.length;

    for (int i = 0; i < numRipples; i++) {
      final ringProgress = i / numRipples;
      final baseRadius = ringProgress * maxRadius;
      final opacity = 0.8 - (ringProgress * 0.3);
      final strokeWidth = 2.0 + (avgAmplitude * 8);

      final path = Path();
      final distortionFactor = avgAmplitude * 30; // Moderate distortion
      final frequencyOffset1 = 3 + (i % 3);
      final frequencyOffset2 = 5 + (i % 4);

      for (int j = 0; j <= numPoints; j++) {
        final angle = (j / numPoints) * 2 * pi;
        final distortion = distortionFactor *
            (sin(frequencyOffset1 * angle + time * 2) * 0.5 +
                cos(frequencyOffset2 * angle - time * 1.5) * 0.3);
        final rotatedAngle = angle + time * 0.2 * (i % 2 == 0 ? 1 : -1);
        final radius = baseRadius + distortion;
        final x = centerX + radius * cos(rotatedAngle);
        final y = centerY + radius * sin(rotatedAngle);

        if (j == 0) {
          path.moveTo(x, y);
        } else {
          final prevAngle = ((j - 1) / numPoints) * 2 * pi + rotatedAngle;
          final controlX = (x + centerX + radius * cos(prevAngle)) / 2;
          final controlY = (y + centerY + radius * sin(prevAngle)) / 2;

          path.quadraticBezierTo(controlX, controlY, x, y);
        }
      }
      path.close();

      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;

      if (avgAmplitude > 0.5) {
        paint.maskFilter = const MaskFilter.blur(BlurStyle.outer, 2);
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant RippleVisualizer oldDelegate) {
    return oldDelegate.time != time || oldDelegate.audioData != audioData;
  }
}
