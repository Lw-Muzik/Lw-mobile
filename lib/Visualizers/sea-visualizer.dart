import 'dart:math';
import 'package:flutter/material.dart';

class OceanVisualizer extends CustomPainter {
  final List<double> audioData;
  final double time;
  final Random random = Random();

  OceanVisualizer({
    required this.audioData,
    required this.time,
  });

  double clamp01(double value) => value.clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    if (audioData.isEmpty) return;

    // Enhanced audio analysis for different wave effects
    final frequencies = List.generate(6, (i) {
      final start = (audioData.length ~/ 6) * i;
      final end = (audioData.length ~/ 6) * (i + 1);
      return clamp01(audioData.sublist(start, end).reduce((a, b) => a + b) /
          (audioData.length / 6));
    });

    final bassIntensity = frequencies[0];
    final midIntensity = (frequencies[2] + frequencies[3]) / 2;
    final highIntensity = frequencies[5];
    final avgAmplitude = clamp01(frequencies.reduce((a, b) => a + b) / 6);

    // Draw sky gradient
    drawSky(canvas, size, avgAmplitude);

    // Draw moon/sun reflection
    drawCelestialReflection(canvas, size, avgAmplitude);

    // Draw multiple wave layers
    final numWaveLayers = 6;
    for (int i = 0; i < numWaveLayers; i++) {
      drawWaveLayer(
        canvas,
        size,
        i,
        numWaveLayers,
        frequencies,
        bassIntensity,
        midIntensity,
        highIntensity,
        avgAmplitude,
      );
    }

    // Draw foam particles
    drawFoamParticles(canvas, size, avgAmplitude);

    // Draw surface highlights
    drawSurfaceHighlights(canvas, size, frequencies, avgAmplitude);
  }

  void drawSky(Canvas canvas, Size size, double intensity) {
    // Create dynamic sky colors based on audio intensity
    final skyColors = [
      Color.lerp(
        const Color(0xFF1A237E), // Deep night blue
        const Color(0xFF3949AB), // Lighter blue
        intensity,
      )!,
      Color.lerp(
        const Color(0xFF000000), // Black
        const Color(0xFF1A237E), // Deep blue
        intensity,
      )!,
    ];

    final skyGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: skyColors,
      stops: const [0.0, 1.0],
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = skyGradient.createShader(
          Rect.fromLTWH(0, 0, size.width, size.height),
        ),
    );
  }

  void drawCelestialReflection(Canvas canvas, Size size, double intensity) {
    final reflectionPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, -0.5),
        radius: 0.5,
        colors: [
          Colors.white.withOpacity(0.3 + (intensity * 0.2)),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(
        Rect.fromLTWH(
          size.width * 0.25,
          -size.height * 0.2,
          size.width * 0.5,
          size.height * 0.8,
        ),
      );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      reflectionPaint,
    );
  }

  void drawWaveLayer(
    Canvas canvas,
    Size size,
    int layer,
    int totalLayers,
    List<double> frequencies,
    double bassIntensity,
    double midIntensity,
    double highIntensity,
    double avgAmplitude,
  ) {
    final progress = layer / totalLayers;
    final baseColor = Color.lerp(
      const Color(0xFF0D47A1), // Deep ocean blue
      const Color(0xFF2196F3), // Light blue
      progress,
    )!;

    final waveColor = Color.lerp(
      baseColor,
      Colors.white,
      progress * 0.3,
    )!;

    final opacity = 0.8 - (progress * 0.3);
    final heightOffset = size.height * (0.5 + (progress * 0.3));

    final path = Path();
    path.moveTo(0, size.height);

    // Number of control points for the wave
    final points = 20;
    final pointDistance = size.width / (points - 1);

    // Different wave frequencies for varied movement
    final waveFreq1 = 2.0 + layer * 0.5;
    final waveFreq2 = 1.5 + layer * 0.3;
    final waveFreq3 = 3.0 + layer * 0.2;

    // Wave amplitudes affected by different frequency bands
    final baseAmplitude = 20.0 * (1 - progress);
    final bassAmp = baseAmplitude * bassIntensity * 2;
    final midAmp = baseAmplitude * midIntensity;
    final highAmp = baseAmplitude * highIntensity * 0.5;

    List<Offset> wavePoints = [];

    for (int i = 0; i <= points; i++) {
      final x = i * pointDistance;
      final xProgress = x / size.width;

      // Combine multiple sine waves for complex movement
      final y = heightOffset +
          sin(time * waveFreq1 + xProgress * 10) * bassAmp +
          sin(time * waveFreq2 + xProgress * 5) * midAmp +
          sin(time * waveFreq3 + xProgress * 15) * highAmp;

      wavePoints.add(Offset(x, y));
    }

    // Create smooth curve through points
    path.moveTo(wavePoints[0].dx, wavePoints[0].dy);

    for (int i = 0; i < wavePoints.length - 1; i++) {
      final current = wavePoints[i];
      final next = wavePoints[i + 1];
      final controlX = (current.dx + next.dx) / 2;
      final controlY = (current.dy + next.dy) / 2;

      path.quadraticBezierTo(
        current.dx,
        current.dy,
        controlX,
        controlY,
      );
    }

    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    // Draw wave with gradient and glow
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          waveColor.withOpacity(opacity),
          waveColor.withOpacity(opacity * 0.7),
        ],
      ).createShader(
        Rect.fromLTWH(0, heightOffset - 50, size.width, 100),
      );

    // Add glow effect for higher frequencies
    if (highIntensity > 0.6) {
      paint.maskFilter = const MaskFilter.blur(BlurStyle.outer, 3);
    }

    canvas.drawPath(path, paint);

    // Add highlights
    if (layer == 0) {
      final highlightPaint = Paint()
        ..color = Colors.white.withOpacity(0.1 + (avgAmplitude * 0.1))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      canvas.drawPath(path, highlightPaint);
    }
  }

  void drawFoamParticles(Canvas canvas, Size size, double intensity) {
    final numParticles = (100 * intensity).toInt();
    final foamPaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    for (int i = 0; i < numParticles; i++) {
      final progress = (time + i * 0.1) % 1.0;
      final x = size.width * ((sin(time * 2 + i) + 1) / 2);
      final y = size.height * (0.4 + progress * 0.2);
      final radius = 1 + random.nextDouble() * 2;

      canvas.drawCircle(
        Offset(x, y),
        radius,
        foamPaint,
      );
    }
  }

  void drawSurfaceHighlights(
    Canvas canvas,
    Size size,
    List<double> frequencies,
    double avgAmplitude,
  ) {
    final numHighlights = (20 * avgAmplitude).toInt();
    final highlightPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withOpacity(0.3),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(
        Rect.fromLTWH(0, 0, 20, 20),
      );

    for (int i = 0; i < numHighlights; i++) {
      final x = size.width * ((sin(time * 3 + i) + 1) / 2);
      final y = size.height * 0.5 + sin(time * 2 + i) * 20;

      canvas.drawCircle(
        Offset(x, y),
        5 + (avgAmplitude * 5),
        highlightPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant OceanVisualizer oldDelegate) {
    return oldDelegate.time != time || oldDelegate.audioData != audioData;
  }
}
