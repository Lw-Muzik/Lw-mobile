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

    // Safe audio analysis with clamped values
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

    // Clamped responses
    final sizeResponse = clamp01(avgAmplitude * 0.6 + maxAmplitude * 0.4);
    final colorResponse = clamp01(lowFreqAmplitude * 0.5 +
        midFreqAmplitude * 0.3 +
        highFreqAmplitude * 0.2);
    final distortionResponse =
        clamp01(midFreqAmplitude * 0.4 + highFreqAmplitude * 0.6);

    final baseRadius = min(width, height) * 0.35;
    final minScale = 0.7;
    final maxScale = 1.6;
    final scale = minScale + (maxScale - minScale) * sizeResponse;

    final numLayers = 25;
    final numPoints = 240;

    // Safe color calculations
    final baseHue = (360 * (time * 0.2 + colorResponse * 0.5)) % 360;
    final baseSaturation =
        clamp01(0.7 + (colorResponse * 0.2)); // Reduced multiplier
    final baseValue =
        clamp01(0.7 + (colorResponse * 0.2)); // Reduced multiplier

    final baseColor = HSVColor.fromAHSV(
      1.0,
      baseHue,
      baseSaturation,
      baseValue,
    ).toColor();

    final accentColor = HSVColor.fromAHSV(
      1.0,
      (baseHue + 180) % 360,
      clamp01(baseSaturation * 0.9),
      clamp01(baseValue * 1.1),
    ).toColor();

    // Shadow effect
    final shadowPaint = Paint()
      ..color = baseColor.withOpacity(clamp01(0.2))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 20 * sizeResponse);

    canvas.drawCircle(
      Offset(centerX, centerY + baseRadius * 0.8),
      baseRadius * scale * 0.8,
      shadowPaint,
    );

    for (int layer = 0; layer < numLayers; layer++) {
      final layerProgress = layer / numLayers;
      final path = Path();

      final layerOpacity = clamp01(0.9 - (layerProgress * 0.6));
      final layerDistortionFactor =
          clamp01(pow(1.0 - layerProgress, 1.5).toDouble());

      for (int i = 0; i <= numPoints; i++) {
        final angle = (i / numPoints) * 2 * pi;

        final baseDistortion = 120.0 * distortionResponse;
        final distortionAmount = baseDistortion * layerDistortionFactor;

        final distortion = distortionAmount *
            (sin(10 * angle + time * 3.0) * 0.3 +
                cos(8 * angle - time * 4.0) * 0.25 +
                sin(15 * angle + time * 5.0) * 0.2 +
                cos(20 * angle - time * 6.0) * 0.15 +
                sin(25 * angle + time * 7.0) * 0.1);

        final dynamicRadius = baseRadius * scale;
        final radius = dynamicRadius + distortion;
        final depthEffect = 0.7 + (sizeResponse * 0.3);
        final sphereEffect =
            clamp01(pow(cos(layerProgress * pi), depthEffect).toDouble());
        final adjustedRadius = radius * sphereEffect;

        final rotationSpeed = 0.8 + (distortionResponse * 1.2);
        final rotationOffset = time * rotationSpeed;
        final rotatedAngle = angle + rotationOffset;

        final x = centerX + adjustedRadius * cos(rotatedAngle);
        final y = centerY + adjustedRadius * sin(rotatedAngle);

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          final prevAngle = ((i - 1) / numPoints) * 2 * pi + rotationOffset;
          final prevRadius = dynamicRadius + distortion;
          final prevSphericalRadius = prevRadius * sphereEffect;
          final prevX = centerX + prevSphericalRadius * cos(prevAngle);
          final prevY = centerY + prevSphericalRadius * sin(prevAngle);

          final tension = clamp01(0.3 + (distortionResponse * 0.2));
          final controlX = (x + prevX) / 2 - (y - prevY) * tension;
          final controlY = (y + prevY) / 2 + (x - prevX) * tension;

          path.quadraticBezierTo(controlX, controlY, x, y);
        }
      }
      path.close();

      final layerColor = Color.lerp(
        baseColor,
        accentColor,
        clamp01(layerProgress * colorResponse),
      )!;

      final paint = Paint()
        ..color = layerColor.withOpacity(layerOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 + (sizeResponse * 3.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      if (distortionResponse > 0.2) {
        paint.maskFilter = MaskFilter.blur(
          BlurStyle.outer,
          3.0 + (distortionResponse * 4.0),
        );
      }

      // Highlights
      if (layer == numLayers - 1) {
        // Primary highlight
        final highlightPaint = Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withOpacity(clamp01(0.6 + (colorResponse * 0.3))),
              Colors.white.withOpacity(0),
            ],
          ).createShader(Rect.fromCircle(
            center: Offset(
              centerX - baseRadius * 0.3,
              centerY - baseRadius * 0.3,
            ),
            radius: baseRadius * 0.6 * scale,
          ))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8);

        canvas.drawCircle(
          Offset(
            centerX - baseRadius * 0.3,
            centerY - baseRadius * 0.3,
          ),
          baseRadius * 0.4 * scale,
          highlightPaint,
        );

        // Secondary highlight
        final smallHighlightPaint = Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withOpacity(clamp01(0.8 + (colorResponse * 0.15))),
              Colors.white.withOpacity(0),
            ],
          ).createShader(Rect.fromCircle(
            center: Offset(
              centerX - baseRadius * 0.4,
              centerY - baseRadius * 0.4,
            ),
            radius: baseRadius * 0.2 * scale,
          ));

        canvas.drawCircle(
          Offset(
            centerX - baseRadius * 0.4,
            centerY - baseRadius * 0.4,
          ),
          baseRadius * 0.15 * scale,
          smallHighlightPaint,
        );
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SphereVisualizer oldDelegate) {
    return oldDelegate.time != time || oldDelegate.audioData != audioData;
  }
}
