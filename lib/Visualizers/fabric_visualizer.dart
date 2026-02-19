import 'dart:math';
import 'package:flutter/material.dart';

class FabricVisualizer extends CustomPainter {
  final List<double> audioData;
  final double time;
  final Random random;

  // Cache frequently used values
  late final List<double> frequencies;
  late final double avgAmplitude;
  late final int gridColumns;
  late final int gridRows;
  late final double cellWidth;
  late final double cellHeight;
  late final Color primaryColor;
  late final Color secondaryColor;

  FabricVisualizer({
    required this.audioData,
    required this.time,
  }) : random = Random() {
    _initializeCache();
  }

  void _initializeCache() {
    if (audioData.isEmpty) return;

    // Cache frequency calculations
    frequencies = _calculateFrequencies();
    avgAmplitude = _calculateAvgAmplitude();

    // Cache grid calculations
    final densityMultiplier = 1.0 + avgAmplitude * 0.5;
    gridColumns = (50 * densityMultiplier).toInt();
    gridRows = (40 * densityMultiplier).toInt();

    // Cache colors
    final baseHue = (200.0 + avgAmplitude * 120) % 360;
    primaryColor = HSVColor.fromAHSV(
      1.0,
      baseHue,
      0.7 + frequencies[0] * 0.3,
      0.8 + frequencies[4] * 0.2,
    ).toColor();

    secondaryColor = HSVColor.fromAHSV(
      1.0,
      (baseHue + 180) % 360,
      0.6 + frequencies[1] * 0.3,
      0.7 + frequencies[3] * 0.3,
    ).toColor();
  }

  List<double> _calculateFrequencies() {
    return List.generate(5, (i) {
      final start = (audioData.length ~/ 5) * i;
      final end = (audioData.length ~/ 5) * (i + 1);
      return (audioData.sublist(start, end).reduce((a, b) => a + b) /
              (audioData.length / 5))
          .clamp(0.0, 1.0);
    });
  }

  double _calculateAvgAmplitude() {
    return (audioData.reduce((a, b) => a + b) / audioData.length)
        .clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (audioData.isEmpty) return;

    cellWidth = size.width / gridColumns;
    cellHeight = size.height / gridRows;

    // Precalculate movement parameters
    final movementParams = _calculateMovementParams();

    // Generate mesh points using more efficient method
    final points = _generateMeshPoints(size, movementParams);

    // Draw fabric with optimized rendering
    _drawFabric(canvas, points, movementParams);

    // Only draw particles if amplitude is significant
    if (avgAmplitude > 0.1) {
      _drawParticles(canvas, size);
    }
  }

  Map<String, double> _calculateMovementParams() {
    return {
      'windSpeed': 2.0 + (frequencies[0] * 4.0),
      'windStrength': 20.0 + (avgAmplitude * 40.0),
      'waveFrequency': 2.0 + (frequencies[4] * 3.0),
      'turbulence': frequencies[2] * 30.0
    };
  }

  List<List<Offset>> _generateMeshPoints(
      Size size, Map<String, double> params) {
    final points = List.generate(gridRows + 1, (row) {
      return List.generate(gridColumns + 1, (col) {
        final progress = col / gridColumns;
        final verticalProgress = row / gridRows;

        // Combine wave calculations
        final x = col * cellWidth;
        final y = row * cellHeight;

        final waveOffset =
            _calculateWaveOffset(col, row, progress, verticalProgress, params);

        return Offset(
          x + waveOffset.dx,
          y + waveOffset.dy,
        );
      });
    });
    return points;
  }

  Offset _calculateWaveOffset(int col, int row, double progress,
      double verticalProgress, Map<String, double> params) {
    final windOffset = sin(time * params['windSpeed']! + col / 3) *
        params['windStrength']! *
        progress;

    final combinedWave =
        sin(time * 2 + progress * pi * params['waveFrequency']!) *
                (15 + frequencies[0] * 25) *
                progress +
            cos(time * 3 +
                    verticalProgress * pi * (params['waveFrequency']! * 1.5)) *
                (10 + frequencies[4] * 20) *
                verticalProgress +
            sin(time * 4 + ((col + row) / (gridColumns + gridRows)) * pi * 2) *
                (5 + frequencies[2] * 15);

    final turbulenceX = random.nextDouble() * params['turbulence']! * progress;
    final turbulenceY =
        random.nextDouble() * params['turbulence']! * verticalProgress;

    return Offset(windOffset + combinedWave + turbulenceX,
        cos(time + col / 5) * (15 + avgAmplitude * 25) + turbulenceY);
  }

  void _drawFabric(
      Canvas canvas, List<List<Offset>> points, Map<String, double> params) {
    final paint = Paint();
    final texturePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5 + (frequencies[4] * 0.5);

    for (int row = 0; row < gridRows; row++) {
      for (int col = 0; col < gridColumns; col++) {
        if (!_isPointVisible(
            points[row][col], Size(cellWidth * 2, cellHeight * 2))) {
          continue;
        }

        final path = _createCellPath(points, row, col);
        _applyCellStyle(canvas, path, paint, row, col);

        // Optimize texture rendering
        if ((row + col) % 3 == 0 && random.nextDouble() < 0.5) {
          _drawTexture(canvas, points[row][col], points[row][col + 1],
              texturePaint, avgAmplitude);
        }
      }
    }
  }

  bool _isPointVisible(Offset point, Size viewArea) {
    return point.dx >= -viewArea.width &&
        point.dx <= viewArea.width &&
        point.dy >= -viewArea.height &&
        point.dy <= viewArea.height;
  }

  Path _createCellPath(List<List<Offset>> points, int row, int col) {
    final path = Path();
    final tension = 0.2 + avgAmplitude * 0.3;

    final p0 = points[row][col];
    final p1 = points[row][col + 1];
    final p2 = points[row + 1][col + 1];
    final p3 = points[row + 1][col];

    path.moveTo(p0.dx, p0.dy);

    // Simplified control points calculation
    _addCurvedEdge(path, p0, p1, tension);
    _addCurvedEdge(path, p1, p2, tension);
    _addCurvedEdge(path, p2, p3, tension);
    _addCurvedEdge(path, p3, p0, tension);

    path.close();
    return path;
  }

  void _addCurvedEdge(Path path, Offset start, Offset end, double tension) {
    final ctrl1 = Offset(start.dx + (end.dx - start.dx) * tension,
        start.dy + (end.dy - start.dy) * tension);
    final ctrl2 = Offset(end.dx - (end.dx - start.dx) * tension,
        end.dy - (end.dy - start.dy) * tension);
    path.cubicTo(ctrl1.dx, ctrl1.dy, ctrl2.dx, ctrl2.dy, end.dx, end.dy);
  }

  void _applyCellStyle(
      Canvas canvas, Path path, Paint paint, int row, int col) {
    final deformation = ((row + col) % 2 == 0) ? 0.3 : 0.5;

    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(primaryColor, Colors.white, deformation * 0.4)!,
        Color.lerp(primaryColor, secondaryColor, deformation * 0.5)!,
        Color.lerp(secondaryColor, Colors.black, deformation * 0.3)!,
      ],
    );

    paint
      ..shader = gradient.createShader(path.getBounds())
      ..style = PaintingStyle.fill;

    if (frequencies[0] > 0.4) {
      paint.maskFilter = MaskFilter.blur(
        BlurStyle.outer,
        2 + (frequencies[0] * 3),
      );
    }

    canvas.drawPath(path, paint);
  }

  void _drawTexture(
      Canvas canvas, Offset start, Offset end, Paint paint, double opacity) {
    paint.color = Colors.white.withValues(alpha: 0.05 + (opacity * 0.1));
    canvas.drawLine(start, end, paint);
  }

  void _drawParticles(Canvas canvas, Size size) {
    final particlePaint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);

    final numParticles = (30 * avgAmplitude).toInt();

    for (int i = 0; i < numParticles; i++) {
      final particleTime = (time * (1.5 + random.nextDouble()) + i) % 1.0;
      if (particleTime < 0.1) continue; // Skip particles just starting

      final particleX = size.width * ((sin(time * 1.5 + i) + 1) / 2);
      final particleY = size.height * particleTime;

      _drawParticleTrail(
          canvas, particlePaint, particleX, particleY, particleTime);
    }
  }

  void _drawParticleTrail(
      Canvas canvas, Paint paint, double x, double y, double particleTime) {
    for (int j = 0; j < 3; j++) {
      final trailOpacity = (0.3 - (j * 0.1)) * (1 - particleTime);
      paint.color = Colors.white.withValues(alpha: trailOpacity);

      canvas.drawCircle(
        Offset(x, y - (j * 2)),
        (3 + (frequencies[4] * 4)) * (1 - (j * 0.3)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant FabricVisualizer oldDelegate) {
    return oldDelegate.time != time || oldDelegate.audioData != audioData;
  }
}
