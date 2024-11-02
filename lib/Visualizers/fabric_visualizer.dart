import 'dart:math';
import 'package:flutter/material.dart';

class FabricVisualizer extends CustomPainter {
  final List<double> audioData;
  final double time;
  final random = Random();

  FabricVisualizer({
    required this.audioData,
    required this.time,
  });

  double clamp01(double value) => value.clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    if (audioData.isEmpty) return;

    // Enhanced audio analysis with frequency bands
    final frequencies = List.generate(5, (i) {
      final start = (audioData.length ~/ 5) * i;
      final end = (audioData.length ~/ 5) * (i + 1);
      return clamp01(audioData.sublist(start, end).reduce((a, b) => a + b) /
          (audioData.length / 5));
    });

    final avgAmplitude =
        clamp01(audioData.reduce((a, b) => a + b) / audioData.length);
    final bassAmplitude = frequencies[0];
    final lowMidAmplitude = frequencies[1];
    final midAmplitude = frequencies[2];
    final highMidAmplitude = frequencies[3];
    final trebleAmplitude = frequencies[4];

    // Enhanced grid configuration with dynamic density
    final baseColumns = 50;
    final baseRows = 40;
    final densityMultiplier = 1.0 + avgAmplitude * 0.5;
    final gridColumns = (baseColumns * densityMultiplier).toInt();
    final gridRows = (baseRows * densityMultiplier).toInt();
    final cellWidth = width / gridColumns;
    final cellHeight = height / gridRows;

    // Enhanced color system
    final baseHue = (200.0 + avgAmplitude * 120) % 360; // Wider color range
    final primaryColor = HSVColor.fromAHSV(
      1.0,
      baseHue,
      0.7 + bassAmplitude * 0.3,
      0.8 + trebleAmplitude * 0.2,
    ).toColor();

    final secondaryColor = HSVColor.fromAHSV(
      1.0,
      (baseHue + 180) % 360,
      0.6 + lowMidAmplitude * 0.3,
      0.7 + highMidAmplitude * 0.3,
    ).toColor();

    // Enhanced movement parameters
    final windSpeed = 2.0 + (bassAmplitude * 4.0);
    final windStrength = 20.0 + (avgAmplitude * 40.0);
    final waveFrequency = 2.0 + (trebleAmplitude * 3.0);
    final turbulence = midAmplitude * 30.0;

    // Create enhanced mesh points with multiple wave patterns
    final points = List.generate(gridRows + 1, (row) {
      return List.generate(gridColumns + 1, (col) {
        final x = col * cellWidth;
        final y = row * cellHeight;
        final progress = col / gridColumns;
        final verticalProgress = row / gridRows;

        // Complex wind movement
        final windOffset =
            sin(time * windSpeed + col / 3) * windStrength * progress;

        // Multiple wave patterns
        final primaryWave =
            sin(time * 2 + (col / gridColumns) * pi * waveFrequency) *
                (15 + bassAmplitude * 25) *
                progress;

        final secondaryWave =
            cos(time * 3 + (row / gridRows) * pi * (waveFrequency * 1.5)) *
                (10 + trebleAmplitude * 20) *
                verticalProgress;

        final tertiaryWave =
            sin(time * 4 + ((col + row) / (gridColumns + gridRows)) * pi * 2) *
                (5 + midAmplitude * 15);

        // Turbulence effect
        final turbulenceX = random.nextDouble() * turbulence * progress;
        final turbulenceY = random.nextDouble() * turbulence * verticalProgress;

        // Combine all movements
        final offsetX = windOffset + primaryWave + secondaryWave + turbulenceX;
        final offsetY = cos(time + col / 5) * (15 + avgAmplitude * 25) +
            tertiaryWave +
            turbulenceY;

        return Offset(
          x + offsetX,
          y + offsetY,
        );
      });
    });

    // Draw enhanced fabric mesh
    for (int row = 0; row < gridRows; row++) {
      for (int col = 0; col < gridColumns; col++) {
        final path = Path();
        final p0 = points[row][col];
        final p1 = points[row][col + 1];
        final p2 = points[row + 1][col + 1];
        final p3 = points[row + 1][col];

        // Dynamic tension based on audio
        final tension = 0.2 + avgAmplitude * 0.3;

        // Enhanced smooth curves
        path.moveTo(p0.dx, p0.dy);

        // Create control points with audio-reactive tension
        final controls = [
          Offset(p0.dx + (p1.dx - p0.dx) * tension,
              p0.dy + (p1.dy - p0.dy) * tension),
          Offset(p1.dx - (p1.dx - p0.dx) * tension,
              p1.dy - (p1.dy - p0.dy) * tension),
          Offset(p1.dx + (p2.dx - p1.dx) * tension,
              p1.dy + (p2.dy - p1.dy) * tension),
          Offset(p2.dx - (p2.dx - p1.dx) * tension,
              p2.dy - (p2.dy - p1.dy) * tension),
          Offset(p2.dx + (p3.dx - p2.dx) * tension,
              p2.dy + (p3.dy - p2.dy) * tension),
          Offset(p3.dx - (p3.dx - p2.dx) * tension,
              p3.dy - (p3.dy - p2.dy) * tension),
          Offset(p3.dx + (p0.dx - p3.dx) * tension,
              p3.dy + (p0.dy - p3.dy) * tension),
          Offset(p0.dx - (p0.dx - p3.dx) * tension,
              p0.dy - (p0.dy - p3.dy) * tension),
        ];

        // Draw smooth curves
        path.cubicTo(controls[0].dx, controls[0].dy, controls[1].dx,
            controls[1].dy, p1.dx, p1.dy);
        path.cubicTo(controls[2].dx, controls[2].dy, controls[3].dx,
            controls[3].dy, p2.dx, p2.dy);
        path.cubicTo(controls[4].dx, controls[4].dy, controls[5].dx,
            controls[5].dy, p3.dx, p3.dy);
        path.cubicTo(controls[6].dx, controls[6].dy, controls[7].dx,
            controls[7].dy, p0.dx, p0.dy);

        path.close();

        // Enhanced lighting and texture effects
        final deformation = (p1.dx - p0.dx).abs() + (p2.dy - p0.dy).abs();
        final normalizedDeformation =
            clamp01(deformation / (cellWidth + cellHeight));

        // Complex gradient based on deformation and audio
        final gradientColors = [
          Color.lerp(primaryColor, Colors.white, normalizedDeformation * 0.4)!,
          Color.lerp(
              primaryColor, secondaryColor, normalizedDeformation * 0.5)!,
          Color.lerp(
              secondaryColor, Colors.black, normalizedDeformation * 0.3)!,
        ];

        final gradient = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
          stops: [0.0, 0.5, 1.0],
        );

        // Enhanced cell rendering
        final paint = Paint()
          ..shader = gradient.createShader(path.getBounds())
          ..style = PaintingStyle.fill;

        // Dynamic shadow effect
        if (bassAmplitude > 0.4) {
          paint.maskFilter = MaskFilter.blur(
            BlurStyle.outer,
            2 + (bassAmplitude * 3),
          );
        }

        canvas.drawPath(path, paint);

        // Enhanced texture details
        if ((row % 2 == 0 || col % 2 == 0) && random.nextDouble() < 0.7) {
          final textureOpacity = 0.05 + (avgAmplitude * 0.1);
          final texturePaint = Paint()
            ..color = Colors.white.withOpacity(textureOpacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5 + (trebleAmplitude * 0.5);

          // Draw fabric texture lines
          if (random.nextBool()) {
            canvas.drawLine(p0, p1, texturePaint);
          } else {
            canvas.drawLine(p1, p2, texturePaint);
          }
        }
      }
    }

    // Enhanced particle system
    final numParticles = (30 * avgAmplitude).toInt();
    for (int i = 0; i < numParticles; i++) {
      final particleTime = (time * (1.5 + random.nextDouble()) + i) % 1.0;
      final particleX = width * ((sin(time * 1.5 + i) + 1) / 2);
      final particleY = height * particleTime;

      // Particle trail effect
      for (int j = 0; j < 3; j++) {
        final trailOpacity = (0.3 - (j * 0.1)) * (1 - particleTime);
        final trailSize = (3 + (trebleAmplitude * 4)) * (1 - (j * 0.3));
        final particlePaint = Paint()
          ..color = Colors.white.withOpacity(trailOpacity)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);

        canvas.drawCircle(
          Offset(particleX, particleY - (j * 2)),
          trailSize,
          particlePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant FabricVisualizer oldDelegate) {
    return oldDelegate.time != time || oldDelegate.audioData != audioData;
  }
}
