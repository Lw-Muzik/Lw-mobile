import 'dart:math';
import 'package:flutter/material.dart';

class HeartbeatVisualizer extends CustomPainter {
  final List<double> audioData;
  final double time;

  HeartbeatVisualizer({
    required this.audioData,
    required this.time,
  });

  double clamp01(double value) {
    return value.clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (audioData.isEmpty) return;

    final width = size.width;
    final height = size.height;
    final centerY = height / 2;

    // Extract frequency amplitudes
    final lowFreqAmplitude = clamp01(
        audioData.sublist(0, audioData.length ~/ 3).reduce((a, b) => a + b) /
            (audioData.length / 3));
    final midFreqAmplitude = clamp01(audioData
            .sublist(audioData.length ~/ 3, 2 * audioData.length ~/ 3)
            .reduce((a, b) => a + b) /
        (audioData.length / 3));
    final highFreqAmplitude = clamp01(
        audioData.sublist(2 * audioData.length ~/ 3).reduce((a, b) => a + b) /
            (audioData.length / 3));

    // Calculate heartbeat parameters
    final beatAmplitude = 30.0 * (0.2 + lowFreqAmplitude * 0.8);
    final beatFrequency = 2.0 + midFreqAmplitude * 3.0; // Affects beat spacing
    final sharpness = 0.3 + highFreqAmplitude * 0.7; // Controls peak sharpness

    // Color based on intensity
    final intensity = (lowFreqAmplitude + midFreqAmplitude) / 2;
    final baseColor = Color.lerp(
      Colors.red[300],
      Colors.red[700],
      intensity,
    )!;

    final paint = Paint()
      ..color = baseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final path = Path();
    bool started = false;

    // Draw the heartbeat pattern
    for (double x = 0; x < width; x += 1) {
      // Basic sine wave for continuous movement
      final baseY = sin((x * beatFrequency * 2 * pi / width) + time * 0.02) *
          beatAmplitude *
          0.3;

      // Add heartbeat peaks
      final phase =
          ((x * beatFrequency * 2 * pi / width) + time * 0.02) % (2 * pi);
      double heartbeatY = baseY;

      // Create the characteristic heartbeat spike
      if (phase < pi) {
        final normalizedPhase = phase / pi;
        if (normalizedPhase < 0.2) {
          // First upward spike
          heartbeatY -= beatAmplitude *
              pow(sin(normalizedPhase * pi / 0.2), sharpness * 2);
        } else if (normalizedPhase < 0.4) {
          // Downward spike
          heartbeatY += beatAmplitude *
              pow(sin((normalizedPhase - 0.2) * pi / 0.2), sharpness);
        } else if (normalizedPhase < 0.5) {
          // Second smaller upward spike
          heartbeatY -= beatAmplitude *
              0.5 *
              pow(sin((normalizedPhase - 0.4) * pi / 0.1), sharpness * 1.5);
        }
      }

      final y = centerY + heartbeatY;

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    // Apply subtle glow effect
    for (double i = 3; i >= 0; i--) {
      final glowPaint = Paint()
        ..color = baseColor.withOpacity(0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = paint.strokeWidth + i * 2;
      canvas.drawPath(path, glowPaint);
    }

    // Draw the main line
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant HeartbeatVisualizer oldDelegate) {
    return oldDelegate.time != time || oldDelegate.audioData != audioData;
  }
}
