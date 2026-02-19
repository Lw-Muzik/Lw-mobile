import 'dart:math';
import 'package:flutter/material.dart';

class OceanVisualizer extends CustomPainter {
  final List<double> audioData;
  final double time;
  final Color color;
  final Random random = Random();

  OceanVisualizer({
    required this.audioData,
    required this.time,
    this.color = Colors.blue,
  });

  double clamp01(double value) => value.clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    if (audioData.isEmpty) return;

    final width = size.width;
    final height = size.height;

    // Pre-calculate intensities and amplitude to avoid redundant calculations
    final frequencies = _calculateFrequencies();
    final bassIntensity = frequencies[0];
    final midIntensity = (frequencies[2] + frequencies[3]) / 2;
    final highIntensity = frequencies[5];
    final avgAmplitude = clamp01(frequencies.reduce((a, b) => a + b) / 6);

    drawSky(canvas, width, height, avgAmplitude);
    drawCelestialReflection(canvas, width, height, avgAmplitude);

    // Number of wave layers reduced dynamically based on amplitude for performance
    final numWaveLayers = (6 * avgAmplitude).ceil();
    for (int i = 0; i < numWaveLayers; i++) {
      drawWaveLayer(
        canvas,
        width,
        height,
        i,
        numWaveLayers,
        frequencies,
        bassIntensity,
        midIntensity,
        highIntensity,
        avgAmplitude,
      );
    }

    drawFoamParticles(canvas, width, height, avgAmplitude);
    drawSurfaceHighlights(canvas, width, height, frequencies, avgAmplitude);
  }

  List<double> _calculateFrequencies() {
    final bandSize = audioData.length ~/ 6;
    return List.generate(6, (i) {
      final start = bandSize * i;
      final end = bandSize * (i + 1);
      return clamp01(
          audioData.sublist(start, end).reduce((a, b) => a + b) / bandSize);
    });
  }

  void drawSky(Canvas canvas, double width, double height, double intensity) {
    final skyColors = [
      Color.lerp(const Color(0xFF1A237E), const Color(0xFF3949AB), intensity)!,
      Color.lerp(const Color(0xFF000000), const Color(0xFF1A237E), intensity)!,
    ];
    final skyGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: skyColors,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()
        ..shader = skyGradient.createShader(Rect.fromLTWH(0, 0, width, height)),
    );
  }

  void drawCelestialReflection(
      Canvas canvas, double width, double height, double intensity) {
    final reflectionPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, -0.5),
        radius: 0.5,
        colors: [
          Colors.white.withValues(alpha: 0.3 + (intensity * 0.2)),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(
          width * 0.25, -height * 0.2, width * 0.5, height * 0.8));

    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      reflectionPaint,
    );
  }

  void drawWaveLayer(
      Canvas canvas,
      double width,
      double height,
      int layer,
      int totalLayers,
      List<double> frequencies,
      double bassIntensity,
      double midIntensity,
      double highIntensity,
      double avgAmplitude) {
    final progress = layer / totalLayers;
    final baseColor = Color.lerp(color, const Color(0xFF2196F3), progress)!;
    final waveColor = Color.lerp(baseColor, Colors.white, progress * 0.3)!;
    final opacity = 0.8 - (progress * 0.3);
    final heightOffset = height * (0.5 + (progress * 0.3));

    final path = Path();
    path.moveTo(0, height);

    final points =
        (20 * avgAmplitude).toInt(); // Fewer points if avgAmplitude is low
    final pointDistance = width / (points - 1);

    final waveFreq1 = 2.0 + layer * 0.5;
    final waveFreq2 = 1.5 + layer * 0.3;
    final waveFreq3 = 3.0 + layer * 0.2;

    final baseAmplitude = 20.0 * (1 - progress);
    final bassAmp = baseAmplitude * bassIntensity * 2;
    final midAmp = baseAmplitude * midIntensity;
    final highAmp = baseAmplitude * highIntensity * 0.5;

    for (int i = 0; i <= points; i++) {
      final x = i * pointDistance;
      final xProgress = x / width;

      final y = heightOffset +
          sin(time * waveFreq1 + xProgress * 10) * bassAmp +
          sin(time * waveFreq2 + xProgress * 5) * midAmp +
          sin(time * waveFreq3 + xProgress * 15) * highAmp;

      path.lineTo(x, y);
    }

    path.lineTo(width, height);
    path.close();

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          waveColor.withValues(alpha: opacity),
          waveColor.withValues(alpha: opacity * 0.7)
        ],
      ).createShader(Rect.fromLTWH(0, heightOffset - 50, width, 100));

    if (highIntensity > 0.6) {
      paint.maskFilter = const MaskFilter.blur(BlurStyle.outer, 3);
    }

    canvas.drawPath(path, paint);
  }

  void drawFoamParticles(
      Canvas canvas, double width, double height, double intensity) {
    final numParticles = (100 * intensity).toInt();
    final foamPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    for (int i = 0; i < numParticles; i++) {
      final progress = (time + i * 0.1) % 1.0;
      final x = width * ((sin(time * 2 + i) + 1) / 2);
      final y = height * (0.4 + progress * 0.2);
      final radius = 1 + random.nextDouble() * 2;

      canvas.drawCircle(Offset(x, y), radius, foamPaint);
    }
  }

  void drawSurfaceHighlights(Canvas canvas, double width, double height,
      List<double> frequencies, double avgAmplitude) {
    final numHighlights = (20 * avgAmplitude).toInt();
    final highlightPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white.withValues(alpha: 0.3), Colors.white.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, 20, 20));

    for (int i = 0; i < numHighlights; i++) {
      final x = width * ((sin(time * 3 + i) + 1) / 2);
      final y = height * 0.5 + sin(time * 2 + i) * 20;

      canvas.drawCircle(Offset(x, y), 5 + (avgAmplitude * 5), highlightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant OceanVisualizer oldDelegate) {
    return oldDelegate.time != time || oldDelegate.audioData != audioData;
  }
}
