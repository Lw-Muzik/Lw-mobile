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

    // Frequency amplitude breakdowns
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

    // Adjusted responses for smoother animation
    final sizeResponse = clamp01(avgAmplitude * 0.5 + maxAmplitude * 0.5);
    final colorResponse = clamp01(lowFreqAmplitude * 0.5 +
        midFreqAmplitude * 0.3 +
        highFreqAmplitude * 0.2);
    final distortionResponse =
        clamp01(midFreqAmplitude * 0.3 + highFreqAmplitude * 0.5);

    final baseRadius = min(width, height) * 0.35;
    final minScale = 0.8;
    final maxScale = 1.3;
    final scale = minScale + (maxScale - minScale) * sizeResponse;

    final numLayers = 20;
    final numPoints = 200;

    // Controlled base hue rotation
    final baseHue = (360 * (time * 0.05 + colorResponse * 0.4)) % 360;
    final baseSaturation = 0.7 + (colorResponse * 0.15);
    final baseValue = 0.8;

    final baseColor = HSVColor.fromAHSV(
      1.0,
      baseHue,
      baseSaturation,
      baseValue,
    ).toColor();

    final accentColor = HSVColor.fromAHSV(
      1.0,
      (baseHue + 180) % 360,
      baseSaturation * 0.9,
      baseValue * 1.05,
    ).toColor();

    // Subtle shadow effect for depth
    final shadowPaint = Paint()
      ..color = baseColor.withOpacity(0.15)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 15 * sizeResponse);

    canvas.drawCircle(
      Offset(centerX, centerY + baseRadius * 0.5),
      baseRadius * scale * 0.7,
      shadowPaint,
    );

    for (int layer = 0; layer < numLayers; layer++) {
      final layerProgress = layer / numLayers;
      final path = Path();

      final layerOpacity = clamp01(0.8 - (layerProgress * 0.6));
      final layerDistortionFactor =
          clamp01(pow(1.0 - layerProgress, 1.5).toDouble());

      for (int i = 0; i <= numPoints; i++) {
        final angle = (i / numPoints) * 2 * pi;

        // Adjusted distortion with reduced frequency influence
        final baseDistortion = 80.0 * distortionResponse;
        final distortionAmount = baseDistortion * layerDistortionFactor;
        final distortion =
            distortionAmount * (sin(8 * angle + time * 2.0) * 0.25);

        final dynamicRadius = baseRadius * scale;
        final radius = dynamicRadius + distortion;
        final sphereEffect = clamp01(
            pow(cos(layerProgress * pi), 0.8 + (sizeResponse * 0.2))
                .toDouble());
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

      // Smooth color transition per layer
      final layerColor = Color.lerp(
        baseColor,
        accentColor,
        clamp01(layerProgress * colorResponse),
      )!;

      final paint = Paint()
        ..color = layerColor.withOpacity(layerOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 + (sizeResponse * 1.5)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      if (distortionResponse > 0.2) {
        paint.maskFilter = MaskFilter.blur(
          BlurStyle.outer,
          2.0 + (distortionResponse * 3.0),
        );
      }

      canvas.drawPath(path, paint);
    }

    // Controlled highlight
    if (numLayers > 1) {
      final highlightPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withOpacity(0.4 + colorResponse * 0.2),
            Colors.white.withOpacity(0),
          ],
        ).createShader(Rect.fromCircle(
          center: Offset(
            centerX - baseRadius * 0.25,
            centerY - baseRadius * 0.25,
          ),
          radius: baseRadius * 0.5 * scale,
        ))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6);

      canvas.drawCircle(
        Offset(
          centerX - baseRadius * 0.25,
          centerY - baseRadius * 0.25,
        ),
        baseRadius * 0.35 * scale,
        highlightPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SphereVisualizer oldDelegate) {
    return oldDelegate.time != time || oldDelegate.audioData != audioData;
  }
}
