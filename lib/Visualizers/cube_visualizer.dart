import 'dart:math';
import 'package:flutter/material.dart';

class CubeVisualizer extends CustomPainter {
  final List<double> audioData;
  final double time;
  final Color color;

  CubeVisualizer({
    required this.audioData,
    required this.time,
    this.color = Colors.blue,
  });

  // Helper function to clamp values between 0 and 1
  double clamp01(double value) {
    return value.clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    if (audioData.isEmpty) return;

    const numCubes = 16;
    const cubeSpacing = 40.0;
    const baseCubeSize = 20.0;

    // Frequency response analysis
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

    final scaleResponse = clamp01(lowFreqAmplitude * 0.6 +
        midFreqAmplitude * 0.3 +
        highFreqAmplitude * 0.2);

    const rotationSpeed = 0.8;
    final rotationOffset = time * rotationSpeed;

    // Cube color
    var baseColor = color;
    const highlightColor = Colors.lightBlueAccent;

    for (int i = 0; i < numCubes; i++) {
      final angle = (i / numCubes) * 2 * pi;
      final cubeSize = baseCubeSize * (1 + scaleResponse * 0.8);

      // Rotation and positioning
      final x = centerX + cos(angle + rotationOffset) * (i * cubeSpacing);
      final y = centerY + sin(angle + rotationOffset) * (i * cubeSpacing);

      // Size scaling based on audio
      final scale = 1.0 + scaleResponse * 1.5;

      // Draw each side of the "cube"
      final paint = Paint()
        ..color = Color.lerp(baseColor, highlightColor, scaleResponse)!;

      canvas.save();
      canvas.translate(x, y);
      canvas.scale(scale);

      final path = Path()
        ..moveTo(-cubeSize / 2, -cubeSize / 2)
        ..lineTo(cubeSize / 2, -cubeSize / 2)
        ..lineTo(cubeSize / 2, cubeSize / 2)
        ..lineTo(-cubeSize / 2, cubeSize / 2)
        ..close();

      canvas.drawPath(path, paint);

      // Draw "depth" sides for a cube effect
      final depthOffset = cubeSize / 4;

      final depthPath = Path()
        ..moveTo(-cubeSize / 2, -cubeSize / 2)
        ..lineTo(-cubeSize / 2 - depthOffset, -cubeSize / 2 - depthOffset)
        ..lineTo(-cubeSize / 2 - depthOffset, cubeSize / 2 - depthOffset)
        ..lineTo(-cubeSize / 2, cubeSize / 2)
        ..close();

      canvas.drawPath(depthPath, paint..color = baseColor.withValues(alpha: 0.7));

      final depthPath2 = Path()
        ..moveTo(cubeSize / 2, -cubeSize / 2)
        ..lineTo(cubeSize / 2 + depthOffset, -cubeSize / 2 - depthOffset)
        ..lineTo(cubeSize / 2 + depthOffset, cubeSize / 2 - depthOffset)
        ..lineTo(cubeSize / 2, cubeSize / 2)
        ..close();

      canvas.drawPath(depthPath2, paint..color = baseColor.withValues(alpha: 0.7));

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CubeVisualizer oldDelegate) {
    return oldDelegate.time != time || oldDelegate.audioData != audioData;
  }
}
