import 'dart:math';
import 'package:flutter/material.dart';

class PhaseLightningVisualizer extends CustomPainter {
  final List<double> audioData;
  final double time;
  final Random random;
  final int numBranches;

  // Cached values and paints for performance
  late final double avgAmplitude;
  late final List<double> frequencies;
  late final Paint corePaint;
  late final Paint glowPaint;
  late final Paint subBranchPaint;
  late final Paint plasmaPaint;
  late final Paint particlePaint;

  PhaseLightningVisualizer({
    required this.audioData,
    required this.time,
    this.numBranches = 5,
  }) : random = Random() {
    _initializeCache();
  }

  void _initializeCache() {
    if (audioData.isEmpty) return;

    // Calculate average amplitude and frequency bands
    avgAmplitude =
        (audioData.reduce((a, b) => a + b) / audioData.length).clamp(0.0, 1.0);
    frequencies = List.generate(4, (i) {
      final segment = audioData.length ~/ 4;
      final start = segment * i;
      final end = segment * (i + 1);
      return (audioData.sublist(start, end).reduce((a, b) => a + b) / segment)
          .clamp(0.0, 1.0);
    });

    // Generate colors based on frequencies
    final hue = (200.0 + frequencies[0] * 160) % 360;
    final primaryColor = HSLColor.fromAHSL(0.8, hue, 0.8, 0.5).toColor();
    final secondaryColor =
        HSLColor.fromAHSL(0.6, (hue + 60) % 360, 0.7, 0.6).toColor();

    // Initialize paints
    corePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 + (avgAmplitude * 3)
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.solid, 2);

    glowPaint = Paint()
      ..color = secondaryColor.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 + (avgAmplitude * 5)
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8);

    subBranchPaint = Paint()
      ..color = primaryColor.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 + (avgAmplitude * 2)
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3);

    plasmaPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          primaryColor.withOpacity(0.2),
          secondaryColor.withOpacity(0.1),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, 500, 500))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 20);

    particlePaint = Paint()
      ..color = primaryColor.withOpacity(0.6)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (audioData.isEmpty) return;

    // Generate and draw branches
    final branches = _generateLightningBranches(size);
    for (final branch in branches) {
      _drawLightningBranch(canvas, branch);
    }

    // Draw plasma and particles
    _drawPlasmaEffects(canvas, size);
    _drawGlowParticles(canvas, size);
  }

  List<List<Offset>> _generateLightningBranches(Size size) {
    final branches = <List<Offset>>[];
    final branchCount = (numBranches + (avgAmplitude * 3)).toInt();

    for (int i = 0; i < branchCount; i++) {
      final startX = size.width * (i / numBranches);
      branches.add(_generateSingleBranch(startX, size.height));
    }

    return branches;
  }

  List<Offset> _generateSingleBranch(double startX, double height) {
    final points = <Offset>[Offset(startX, 0.0)];
    final segments = 10 + (frequencies[0] * 10).toInt();
    final segmentHeight = height / segments;

    for (int i = 1; i <= segments; i++) {
      final xOffset = (random.nextDouble() - 0.5) *
          30.0 *
          (1 + frequencies[1] + frequencies[2]);
      final timeOffset = sin(time * 2 + i) * 20 * frequencies[3];
      points.add(Offset(startX + xOffset + timeOffset, i * segmentHeight));
    }

    return points;
  }

  void _drawLightningBranch(Canvas canvas, List<Offset> points) {
    final path = Path()..moveTo(points[0].dx, points[0].dy);

    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final current = points[i];
      final mid =
          Offset((prev.dx + current.dx) / 2, (prev.dy + current.dy) / 2);
      path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }

    // Draw the branch and its glow
    canvas.drawPath(path, corePaint);
    canvas.drawPath(path, glowPaint);

    // Draw sub-branches
    _drawSubBranches(canvas, points);
  }

  void _drawSubBranches(Canvas canvas, List<Offset> mainPoints) {
    for (int i = 1; i < mainPoints.length - 1; i++) {
      if (random.nextDouble() < 0.3 * frequencies[2]) {
        final start = mainPoints[i];
        final angle = random.nextDouble() * pi / 2 - pi / 4;
        final length = 20.0 + random.nextDouble() * 30.0 * frequencies[1];
        final end = Offset(
            start.dx + cos(angle) * length, start.dy + sin(angle) * length);

        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, end.dy);
        canvas.drawPath(path, subBranchPaint);
      }
    }
  }

  void _drawPlasmaEffects(Canvas canvas, Size size) {
    for (int i = 0; i < 3; i++) {
      final center = Offset(size.width * (0.3 + random.nextDouble() * 0.4),
          size.height * (0.3 + random.nextDouble() * 0.4));
      canvas.drawCircle(center, 50 + (frequencies[i] * 100), plasmaPaint);
    }
  }

  void _drawGlowParticles(Canvas canvas, Size size) {
    final particleCount = (20 * avgAmplitude).toInt();
    for (int i = 0; i < particleCount; i++) {
      final x = size.width * random.nextDouble();
      final y = size.height * ((time * 2 + i) % 1.0);
      canvas.drawCircle(Offset(x, y), 2 + (frequencies[3] * 4), particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant PhaseLightningVisualizer oldDelegate) {
    return oldDelegate.time != time || oldDelegate.audioData != audioData;
  }
}
