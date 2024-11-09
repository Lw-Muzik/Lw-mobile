import 'dart:math';
import 'package:flutter/material.dart';

class SphereVisualizer extends CustomPainter {
  final List<double> audioData;
  final double time;

  SphereVisualizer({
    required this.audioData,
    required this.time,
  });

  // Helper function to clamp values between 0 and 1
  double clamp01(double value) {
    return value.clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final centerX = width / 2;
    final centerY = height / 2;

    if (audioData.isEmpty) return;

    // Amplitude breakdowns, cached to avoid redundant calculations
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

    final avgAmplitude =
        clamp01(audioData.reduce((a, b) => a + b) / audioData.length);
    final maxAmplitude = clamp01(audioData.reduce(max));

    final sizeResponse = clamp01(avgAmplitude * 0.5 + maxAmplitude * 0.5);
    final colorResponse = clamp01(lowFreqAmplitude * 0.5 +
        midFreqAmplitude * 0.3 +
        highFreqAmplitude * 0.2);
    final distortionResponse =
        clamp01(midFreqAmplitude * 0.3 + highFreqAmplitude * 0.5);

    // Optimize number of layers and points for smoother performance
    final baseRadius = min(width, height) * 0.35;
    final numLayers = 12; // Reduced from 20
    final numPoints = 120; // Reduced from 200
    final minScale = 0.8;
    final maxScale = 1.2; // Slightly reduced for a smoother transition
    final scale = minScale + (maxScale - minScale) * sizeResponse;

    // Calculated once outside loop for reuse
    final baseHue = (360 * (time * 0.05 + colorResponse * 0.4)) % 360;
    final baseColor = HSVColor.fromAHSV(1.0, baseHue, 0.7, 0.8).toColor();
    final accentColor =
        HSVColor.fromAHSV(1.0, (baseHue + 180) % 360, 0.6, 0.8).toColor();

    // Draw background shadow once
    final shadowPaint = Paint()
      ..color = baseColor.withOpacity(0.15)
      ..maskFilter = MaskFilter.blur(
          BlurStyle.normal, 10 * sizeResponse); // Adjusted blur strength

    canvas.drawCircle(Offset(centerX, centerY + baseRadius * 0.5),
        baseRadius * scale * 0.7, shadowPaint);

    for (int layer = 0; layer < numLayers; layer++) {
      final layerProgress = layer / numLayers;
      final path = Path();

      final layerOpacity = clamp01(0.8 - (layerProgress * 0.5));
      final layerDistortionFactor = pow(1.0 - layerProgress, 1.5).toDouble();

      for (int i = 0; i <= numPoints; i++) {
        final angle = (i / numPoints) * 2 * pi;
        final baseDistortion =
            60.0 * distortionResponse; // Reduced distortion value
        final distortionAmount = baseDistortion * layerDistortionFactor;
        final distortion =
            distortionAmount * (sin(8 * angle + time * 2.0) * 0.25);

        final radius = baseRadius * scale + distortion;
        final sphereEffect =
            pow(cos(layerProgress * pi), 0.8 + sizeResponse * 0.2).toDouble();
        final adjustedRadius = radius * sphereEffect;

        final x = centerX + adjustedRadius * cos(angle);
        final y = centerY + adjustedRadius * sin(angle);

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();

      // Layer color calculation, performed outside the loop for each layer
      final layerColor = Color.lerp(
          baseColor, accentColor, clamp01(layerProgress * colorResponse))!;
      final paint = Paint()
        ..color = layerColor.withOpacity(layerOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 + sizeResponse * 1.0;

      canvas.drawPath(path, paint);
    }

    // Add a soft highlight if needed, now simpler and more performant
    if (numLayers > 1) {
      final highlightPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withOpacity(0.4 + colorResponse * 0.2),
            Colors.transparent
          ],
        ).createShader(Rect.fromCircle(
            center: Offset(
                centerX - baseRadius * 0.25, centerY - baseRadius * 0.25),
            radius: baseRadius * 0.5 * scale));

      canvas.drawCircle(
          Offset(centerX - baseRadius * 0.25, centerY - baseRadius * 0.25),
          baseRadius * 0.35 * scale,
          highlightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant SphereVisualizer oldDelegate) {
    return oldDelegate.time != time || oldDelegate.audioData != audioData;
  }
}
