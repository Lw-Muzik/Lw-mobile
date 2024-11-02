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

  double clamp01(double value) => value.clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final center = Offset(width / 2, height / 2);

    if (audioData.isEmpty) return;

    // Enhanced audio analysis
    final frequencies = List.generate(6, (i) {
      final start = (audioData.length ~/ 6) * i;
      final end = (audioData.length ~/ 6) * (i + 1);
      return clamp01(audioData.sublist(start, end).reduce((a, b) => a + b) /
          (audioData.length / 6));
    });

    final avgAmplitude = clamp01(frequencies.reduce((a, b) => a + b) / 6);

    // Color palette for neon effects
    final colors = [
      Colors.blue,
      Colors.purple,
      Colors.pink,
      Colors.orange,
      Colors.yellow,
      Colors.white,
    ];

    // Draw multiple layers of patterns
    for (int layer = 0; layer < 3; layer++) {
      final scale = 1.0 - (layer * 0.2);
      drawKaleidoscopeLayer(
        canvas,
        center,
        size,
        scale,
        colors,
        frequencies,
        avgAmplitude,
        layer,
      );
    }

    // Add central pattern
    drawCenterPattern(canvas, center, frequencies, colors, avgAmplitude);

    // Add floating particles
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
    int layer,
  ) {
    final numSegments = 8;
    final radius = min(size.width, size.height) * 0.4 * scale;

    for (int i = 0; i < numSegments; i++) {
      final angle = (2 * pi * i) / numSegments;
      final rotationOffset = time * (1 + layer) * 0.2;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle + rotationOffset);

      // Draw geometric patterns
      drawGeometricPattern(
        canvas,
        radius,
        colors,
        frequencies,
        avgAmplitude,
        layer,
      );

      canvas.restore();
    }
  }

  void drawGeometricPattern(
    Canvas canvas,
    double radius,
    List<Color> colors,
    List<double> frequencies,
    double avgAmplitude,
    int layer,
  ) {
    final baseSize = radius * 0.2;
    final patterns = [
      drawCirclePattern,
      drawDiamondPattern,
      drawFlowerPattern,
    ];

    patterns[layer](
      canvas,
      baseSize,
      colors,
      frequencies,
      avgAmplitude,
    );
  }

  void drawCirclePattern(
    Canvas canvas,
    double size,
    List<Color> colors,
    List<double> frequencies,
    double avgAmplitude,
  ) {
    final circles = 4;
    for (int i = 0; i < circles; i++) {
      final progress = i / circles;
      final frequency = frequencies[i % frequencies.length];
      final color = colors[i % colors.length];

      final paint = Paint()
        ..color = color.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 + (frequency * 3)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.outer,
          2 + (frequency * 4),
        );

      final radius = size * (0.5 + progress) * (1 + frequency * 0.3);
      canvas.drawCircle(Offset.zero, radius, paint);

      // Add inner glow
      final glowPaint = Paint()
        ..color = color.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          3 + (frequency * 2),
        );

      canvas.drawCircle(Offset.zero, radius * 0.9, glowPaint);
    }
  }

  void drawDiamondPattern(
    Canvas canvas,
    double size,
    List<Color> colors,
    List<double> frequencies,
    double avgAmplitude,
  ) {
    final diamonds = 3;
    for (int i = 0; i < diamonds; i++) {
      final progress = i / diamonds;
      final frequency = frequencies[(i + 2) % frequencies.length];
      final color = colors[(i + 1) % colors.length];

      final paint = Paint()
        ..color = color.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 + (frequency * 3)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.outer,
          2 + (frequency * 4),
        );

      final path = Path();
      final diamondSize = size * (0.7 + progress) * (1 + frequency * 0.3);

      path.moveTo(0, -diamondSize);
      path.lineTo(diamondSize, 0);
      path.lineTo(0, diamondSize);
      path.lineTo(-diamondSize, 0);
      path.close();

      canvas.drawPath(path, paint);

      // Add inner glow
      final glowPaint = Paint()
        ..color = color.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          3 + (frequency * 2),
        );

      canvas.drawPath(path, glowPaint);
    }
  }

  void drawFlowerPattern(
    Canvas canvas,
    double size,
    List<Color> colors,
    List<double> frequencies,
    double avgAmplitude,
  ) {
    final petals = 6;
    final frequency = frequencies[3];
    final color = colors[2];

    final paint = Paint()
      ..color = color.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 + (frequency * 3)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.outer,
        2 + (frequency * 4),
      );

    final path = Path();
    for (int i = 0; i < petals; i++) {
      final angle = (2 * pi * i) / petals;
      final petalSize = size * (1 + frequency * 0.3);

      path.addArc(
        Rect.fromCenter(
          center: Offset(petalSize * 0.5, 0),
          width: petalSize,
          height: petalSize * 0.5,
        ),
        0,
        pi,
      );

      canvas.save();
      canvas.rotate(angle);
      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  void drawCenterPattern(
    Canvas canvas,
    Offset center,
    List<double> frequencies,
    List<Color> colors,
    double avgAmplitude,
  ) {
    final size = min(center.dx, center.dy) * 0.15;
    final pattern = Path();
    final segments = 4;

    for (int i = 0; i < segments; i++) {
      final angle = (2 * pi * i) / segments;
      final frequency = frequencies[i % frequencies.length];
      final color = colors[i % colors.length];

      final paint = Paint()
        ..color = color.withOpacity(0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 + (frequency * 4)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.outer,
          3 + (frequency * 5),
        );

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle + time * 0.5);

      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: size * (1 + frequency * 0.4),
        height: size * (1 + frequency * 0.4),
      );

      pattern.addRect(rect);
      canvas.drawPath(pattern, paint);
      canvas.restore();
    }
  }

  void drawParticles(
    Canvas canvas,
    Size size,
    List<double> frequencies,
    double avgAmplitude,
  ) {
    final numParticles = (50 * avgAmplitude).toInt();

    for (int i = 0; i < numParticles; i++) {
      final progress = (time * 0.5 + i * 0.1) % 1.0;
      final angle = 2 * pi * progress;
      final radius = min(size.width, size.height) * 0.5 * progress;
      final color = Colors.white;

      final x = size.width / 2 + cos(angle) * radius;
      final y = size.height / 2 + sin(angle) * radius;

      final paint = Paint()
        ..color = color.withOpacity((1 - progress) * 0.5)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          2 + (avgAmplitude * 3),
        );

      canvas.drawCircle(
        Offset(x, y),
        2 + (avgAmplitude * 3),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PlasmaVisualizer oldDelegate) {
    return oldDelegate.time != time || oldDelegate.audioData != audioData;
  }
}
