import 'dart:math';
import 'package:flutter/material.dart';

class RippleVisualizer extends CustomPainter {
  final List<double> audioData;
  final double time;

  RippleVisualizer({
    required this.audioData,
    required this.time,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final centerX = width / 2;
    final centerY = height / 2;

    // Increased number of rings for better visual effect
    const numRipples = 8;

    if (audioData.isNotEmpty) {
      // Calculate average amplitude
      final avgAmplitude = audioData.reduce((a, b) => a + b) / audioData.length;

      for (int i = 0; i < numRipples; i++) {
        // Static ring positions instead of expanding
        final ringProgress = i / numRipples;
        final maxRadius = width < height ? width / 2.5 : height / 2.5;
        final baseRadius = ringProgress * maxRadius;

        // Fade out outer rings slightly
        final opacity = 0.8 - (ringProgress * 0.3);

        // Dynamic stroke width based on audio
        final strokeWidth = 2.0 + (avgAmplitude * 8);

        const numPoints = 180; // Increased points for smoother distortion
        final path = Path();

        for (int j = 0; j <= numPoints; j++) {
          final angle = (j / numPoints) * 2 * pi;

          // Create complex distortion using multiple sine waves
          final distortionFactor = avgAmplitude * 40; // Increased distortion

          // Use different frequencies for each ring
          final frequency1 = 4 + (i % 3) * 2;
          final frequency2 = 6 + (i % 4);

          // Layer multiple distortions
          final distortion = distortionFactor *
              (sin(frequency1 * angle + time * 3) * 0.6 +
                  cos(frequency2 * angle - time * 2) * 0.4 +
                  sin((8 + i) * angle + time * 4) * 0.3 * avgAmplitude);

          // Add slight rotation to each ring
          final rotationOffset =
              time * (i % 2 == 0 ? 1 : -1) + (i * pi / numRipples);
          final rotatedAngle = angle + rotationOffset;

          final radius = baseRadius + distortion;
          final x = centerX + radius * cos(rotatedAngle);
          final y = centerY + radius * sin(rotatedAngle);

          if (j == 0) {
            path.moveTo(x, y);
          } else {
            // Use quadratic curve for smoother lines
            final prevAngle = ((j - 1) / numPoints) * 2 * pi + rotationOffset;
            final prevRadius = baseRadius + distortion;
            final prevX = centerX + prevRadius * cos(prevAngle);
            final prevY = centerY + prevRadius * sin(prevAngle);

            final controlX = (x + prevX) / 2;
            final controlY = (y + prevY) / 2;

            path.quadraticBezierTo(controlX, controlY, x, y);
          }
        }
        path.close();

        // Create gradient effect
        final paint = Paint()
          ..color = Colors.blue.withOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        // Add glow effect for higher amplitudes
        if (avgAmplitude > 0.5) {
          paint.maskFilter = const MaskFilter.blur(BlurStyle.outer, 3);
        }

        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant RippleVisualizer oldDelegate) {
    return oldDelegate.time != time || oldDelegate.audioData != audioData;
  }
}
