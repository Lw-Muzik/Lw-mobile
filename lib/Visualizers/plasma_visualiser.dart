import 'dart:math';
import 'package:flutter/material.dart';

class PlasmaVisualizer extends CustomPainter {
  final List<double> audioData;
  final double time;
  final Random random = Random();

  PlasmaVisualizer({
    required this.audioData,
    required this.time,
  });

  static final Paint _circlePaint = Paint()..style = PaintingStyle.stroke;
  static final Paint _diamondPaint = Paint()..style = PaintingStyle.stroke;
  static final Paint _particlePaint = Paint()..color = Colors.white;

  double clamp01(double value) => value.clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final center = Offset(width / 2, height / 2);

    if (audioData.isEmpty) return;

    // Optimized frequency calculations
    final frequencies = List.generate(
      6,
      (i) {
        if (audioData.length < 6) return 0.0;
        final start = (audioData.length ~/ 6) * i;
        final end = (audioData.length ~/ 6) * (i + 1);
        return clamp01(audioData.sublist(start, end).reduce((a, b) => a + b) /
            (audioData.length / 6));
      },
    );

    final avgAmplitude =
        clamp01(frequencies.reduce((a, b) => a + b) / frequencies.length);
    if (avgAmplitude < 0.05) return;

    final colors = [
      Colors.blue,
      Colors.purple,
      Colors.pink,
      Colors.orange,
      Colors.yellow,
      Colors.white
    ];

    // Reduced layers for smoother performance
    for (int layer = 0; layer < 3; layer++) {
      final scale = 1.0 - (layer * 0.2) * (1 + avgAmplitude);
      drawKaleidoscopeLayer(canvas, center, size, scale, colors, frequencies,
          avgAmplitude, layer);
    }

    drawCenterPattern(canvas, center, frequencies, colors, avgAmplitude);
    drawParticles(canvas, size, frequencies, avgAmplitude);
  }

  void drawKaleidoscopeLayer(
      Canvas canvas,
      Offset center,
      Size size,
      double scale,
      List<Color> colors,
      List<double> frequencies,
      double avgAmplitude,
      int layer) {
    final radius = min(size.width, size.height) * 0.4 * scale;

    for (int i = 0; i < 8; i++) {
      final angle = (2 * pi * i) / 8;
      final rotationOffset = time * (1 + layer) * 0.3 * avgAmplitude;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle + rotationOffset);
      drawGeometricPattern(
          canvas, radius, colors, frequencies, avgAmplitude, layer);
      canvas.restore();
    }
  }

  void drawGeometricPattern(Canvas canvas, double radius, List<Color> colors,
      List<double> frequencies, double avgAmplitude, int layer) {
    final baseSize = radius * 0.2 * (1 + avgAmplitude);
    final patternFuncs = [drawCirclePattern, drawDiamondPattern];
    patternFuncs[layer % patternFuncs.length](
        canvas, baseSize, colors, frequencies, avgAmplitude);
  }

  void drawCirclePattern(Canvas canvas, double size, List<Color> colors,
      List<double> frequencies, double avgAmplitude) {
    for (int i = 0; i < 4; i++) {
      final progress = i / 4;
      final frequency = frequencies[i % frequencies.length];
      final color = colors[i % colors.length];

      _circlePaint
        ..color = color.withOpacity(0.6 + avgAmplitude * 0.3)
        ..strokeWidth = 2 + (frequency * 2);

      final radius = size * (0.5 + progress) * (1 + frequency * 0.3);
      canvas.drawCircle(Offset.zero, radius, _circlePaint);
    }
  }

  void drawDiamondPattern(Canvas canvas, double size, List<Color> colors,
      List<double> frequencies, double avgAmplitude) {
    final diamonds = 3;
    for (int i = 0; i < diamonds; i++) {
      final progress = i / diamonds;
      final frequency = frequencies[(i + 2) % frequencies.length];
      final color = colors[(i + 1) % colors.length];

      _diamondPaint
        ..color = color.withOpacity(0.6 + avgAmplitude * 0.2)
        ..strokeWidth = 2 + (frequency * 1.5);

      final diamondSize = size * (0.7 + progress) * (1 + frequency * 0.2);
      final path = Path()
        ..moveTo(0, -diamondSize)
        ..lineTo(diamondSize, 0)
        ..lineTo(0, diamondSize)
        ..lineTo(-diamondSize, 0)
        ..close();

      canvas.drawPath(path, _diamondPaint);
    }
  }

  void drawCenterPattern(Canvas canvas, Offset center, List<double> frequencies,
      List<Color> colors, double avgAmplitude) {
    final size = min(center.dx, center.dy) * 0.2 * (1 + avgAmplitude);
    final segments = 4;

    // Reduced unnecessary path creation inside loop
    for (int i = 0; i < segments; i++) {
      final frequency = frequencies[i % frequencies.length];
      final color = colors[i % colors.length];

      _circlePaint
        ..color = color.withOpacity(0.7 + avgAmplitude * 0.3)
        ..strokeWidth = 2 + (frequency * 2);

      final rect = Rect.fromCenter(
          center: Offset.zero,
          width: size * (1 + frequency * 0.2),
          height: size * (1 + frequency * 0.2));

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(i * (2 * pi / segments) + time * 0.5);
      canvas.drawRect(rect, _circlePaint);
      canvas.restore();
    }
  }

  void drawParticles(
      Canvas canvas, Size size, List<double> frequencies, double avgAmplitude) {
    final numParticles = (20 * avgAmplitude).toInt();
    for (int i = 0; i < numParticles; i++) {
      final progress = (time * 0.5 + i * 0.1) % 1.0;
      final angle = 2 * pi * progress;
      final radius = min(size.width, size.height) * 0.5 * progress;

      _particlePaint.color = Colors.white.withOpacity((1 - progress) * 0.5);

      canvas.drawCircle(
        Offset(size.width / 2 + cos(angle) * radius,
            size.height / 2 + sin(angle) * radius),
        2 + (avgAmplitude * 2),
        _particlePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PlasmaVisualizer oldDelegate) {
    return oldDelegate.time != time || oldDelegate.audioData != audioData;
  }
}
