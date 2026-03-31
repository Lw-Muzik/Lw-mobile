import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Shared helpers
// ═════════════════════════════════════════════════════════════════════════════

double _band(List<double> data, int i, int total) {
  if (data.isEmpty) return 0.0;
  return data[(i * data.length / total).floor().clamp(0, data.length - 1)].clamp(0.0, 1.0);
}

double _smoothBand(List<double> data, int i, int total) {
  if (data.isEmpty) return 0.0;
  final idx = (i * data.length / total).floor().clamp(0, data.length - 1);
  final spread = math.max(1, data.length ~/ total);
  double sum = 0;
  int count = 0;
  for (int j = -spread; j <= spread; j++) {
    sum += data[(idx + j).clamp(0, data.length - 1)];
    count++;
  }
  return (sum / count).clamp(0.0, 1.0);
}

// ═════════════════════════════════════════════════════════════════════════════
// 13. METABALL BLOB — Merging soft blobs that pulse with audio
// ═════════════════════════════════════════════════════════════════════════════

class MetaballBlobVisualizer extends CustomPainter {
  final List<double> audioData;
  final Color color;
  final double time;

  static const int _blobCount = 4;
  static const int _gridSize = 28;

  MetaballBlobVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = math.min(cx, cy);
    if (audioData.isEmpty) return;

    // Separate bass/mids
    double bass = 0, mids = 0;
    final bassEnd = audioData.length ~/ 4;
    final midsEnd = audioData.length ~/ 2;
    for (int i = 0; i < bassEnd; i++) bass += audioData[i];
    for (int i = bassEnd; i < midsEnd; i++) mids += audioData[i];
    bass = (bass / bassEnd).clamp(0.0, 1.0);
    mids = (mids / (midsEnd - bassEnd)).clamp(0.0, 1.0);

    // Blob centers — orbit around center, bass pushes them apart
    final blobs = <(double x, double y, double r)>[];
    for (int i = 0; i < _blobCount; i++) {
      final angle = (i / _blobCount) * math.pi * 2 + time * 0.8;
      final bandAmp = _band(audioData, i, _blobCount);
      final dist = maxR * 0.2 * (1.0 + bass * 1.2 + bandAmp * 0.8);
      final bx = cx + math.cos(angle) * dist + math.sin(time * 1.3 + i * 2) * 25 * (1 + bandAmp);
      final by = cy + math.sin(angle) * dist + math.cos(time * 1.1 + i * 3) * 25 * (1 + bandAmp);
      final br = maxR * (0.2 + bandAmp * 0.18 + bass * 0.12);
      blobs.add((bx, by, br));
    }

    // Marching squares on grid — evaluate metaball field
    final cellW = size.width / _gridSize;
    final cellH = size.height / _gridSize;
    // Evaluate field at grid intersections
    final field = List.generate(_gridSize + 1, (gy) =>
      List.generate(_gridSize + 1, (gx) {
        final px = gx * cellW;
        final py = gy * cellH;
        double sum = 0;
        for (final (bx, by, br) in blobs) {
          final dx = px - bx;
          final dy = py - by;
          final distSq = dx * dx + dy * dy;
          sum += (br * br) / (distSq + 1);
        }
        return sum;
      }),
    );

    // Draw contour lines using marching squares
    final contourPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..isAntiAlias = true;

    // Multiple contour levels for depth
    final levels = [0.6, 1.5];
    for (int lvl = 0; lvl < levels.length; lvl++) {
      final iso = levels[lvl];
      final alpha = (0.15 + (lvl / levels.length) * 0.5).clamp(0.1, 0.7);
      contourPaint
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = 1.0 + lvl * 0.5;

      if (lvl == levels.length - 1) {
        contourPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      } else {
        contourPaint.maskFilter = null;
      }

      for (int gy = 0; gy < _gridSize; gy++) {
        for (int gx = 0; gx < _gridSize; gx++) {
          final tl = field[gy][gx];
          final tr = field[gy][gx + 1];
          final br = field[gy + 1][gx + 1];
          final bl = field[gy + 1][gx];

          // Classify corners
          int caseIdx = 0;
          if (tl >= iso) caseIdx |= 1;
          if (tr >= iso) caseIdx |= 2;
          if (br >= iso) caseIdx |= 4;
          if (bl >= iso) caseIdx |= 8;

          if (caseIdx == 0 || caseIdx == 15) continue;

          final x0 = gx * cellW;
          final y0 = gy * cellH;

          // Interpolate edge crossings
          // ignore: no_leading_underscores_for_local_identifiers
          Offset _lerp(double v1, double v2, double x1, double y1, double x2, double y2) {
            final t = (iso - v1) / (v2 - v1 + 1e-10);
            return Offset(x1 + t * (x2 - x1), y1 + t * (y2 - y1));
          }

          final top = _lerp(tl, tr, x0, y0, x0 + cellW, y0);
          final right = _lerp(tr, br, x0 + cellW, y0, x0 + cellW, y0 + cellH);
          final bottom = _lerp(bl, br, x0, y0 + cellH, x0 + cellW, y0 + cellH);
          final left = _lerp(tl, bl, x0, y0, x0, y0 + cellH);

          // Draw contour segments based on case
          void drawSeg(Offset a, Offset b) => canvas.drawLine(a, b, contourPaint);

          switch (caseIdx) {
            case 1: case 14: drawSeg(top, left);
            case 2: case 13: drawSeg(top, right);
            case 3: case 12: drawSeg(left, right);
            case 4: case 11: drawSeg(right, bottom);
            case 5: drawSeg(top, right); drawSeg(bottom, left);
            case 6: case 9: drawSeg(top, bottom);
            case 7: case 8: drawSeg(left, bottom);
            case 10: drawSeg(top, left); drawSeg(right, bottom);
          }
        }
      }
    }

    // Inner glow at each blob center
    for (final (bx, by, br) in blobs) {
      canvas.drawCircle(Offset(bx, by), br * 0.8, Paint()
        ..shader = ui.Gradient.radial(
          Offset(bx, by), br * 0.8,
          [color.withValues(alpha: 0.2), color.withValues(alpha: 0.0)],
        ));
    }
  }

  @override
  bool shouldRepaint(covariant MetaballBlobVisualizer old) => true;
}

// ═════════════════════════════════════════════════════════════════════════════
// 14. MILKDROP WARP MESH — Grid with per-vertex displacement + color smearing
// ═════════════════════════════════════════════════════════════════════════════

class MilkdropWarpVisualizer extends CustomPainter {
  final List<double> audioData;
  final Color color;
  final double time;

  static const int _gridW = 24;
  static const int _gridH = 18;

  MilkdropWarpVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (audioData.isEmpty) return;

    double bass = 0, mids = 0, treble = 0;
    final len = audioData.length;
    final q = len ~/ 3;
    for (int i = 0; i < q; i++) bass += audioData[i];
    for (int i = q; i < q * 2; i++) mids += audioData[i];
    for (int i = q * 2; i < len; i++) treble += audioData[i];
    bass = (bass / q).clamp(0.0, 1.0);
    mids = (mids / q).clamp(0.0, 1.0);
    treble = (treble / (len - q * 2)).clamp(0.0, 1.0);

    // Zoom/rotation driven by audio — strong response
    final zoom = 1.0 + bass * 0.35;
    final rot = time * 0.3 + mids * 1.2;
    final warpStrength = 0.06 + treble * 0.14 + bass * 0.08;

    final cx = w / 2;
    final cy = h / 2;
    final cosR = math.cos(rot);
    final sinR = math.sin(rot);

    // Build warped grid
    final points = List.generate(_gridH + 1, (gy) =>
      List.generate(_gridW + 1, (gx) {
        // Normalized coords -1..1
        var nx = (gx / _gridW) * 2.0 - 1.0;
        var ny = (gy / _gridH) * 2.0 - 1.0;

        // Warp: zoom toward center + rotate
        nx = nx * zoom;
        ny = ny * zoom;

        // Rotate
        final rx = nx * cosR - ny * sinR;
        final ry = nx * sinR + ny * cosR;

        // Per-vertex wave displacement
        final waveX = math.sin(ry * math.pi * 3 + time * 4) * warpStrength;
        final waveY = math.cos(rx * math.pi * 3 + time * 3) * warpStrength;

        // Audio displacement from frequency bands
        final bandAmp = _smoothBand(audioData, gx, _gridW + 1);
        final audioDisplace = bandAmp * 0.12;

        final finalX = (rx + waveX + audioDisplace) * 0.5 + 0.5;
        final finalY = (ry + waveY) * 0.5 + 0.5;

        return Offset(finalX * w, finalY * h);
      }),
    );

    // Draw grid
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    // Horizontal lines
    for (int gy = 0; gy <= _gridH; gy++) {
      final path = Path();
      for (int gx = 0; gx <= _gridW; gx++) {
        final p = points[gy][gx];
        if (gx == 0) path.moveTo(p.dx, p.dy); else path.lineTo(p.dx, p.dy);
      }

      final t = gy / _gridH;
      final amp = _smoothBand(audioData, gy, _gridH + 1);
      final alpha = (0.15 + amp * 0.55).clamp(0.08, 0.7);
      // Color variation across grid
      final hue = (HSLColor.fromColor(color).hue + t * 60 + time * 30) % 360;
      paint
        ..color = HSLColor.fromAHSL(alpha, hue, 0.8, 0.55).toColor()
        ..strokeWidth = 0.8 + amp * 1.8;
      canvas.drawPath(path, paint);
    }

    // Vertical lines
    for (int gx = 0; gx <= _gridW; gx += 2) {
      final path = Path();
      for (int gy = 0; gy <= _gridH; gy++) {
        final p = points[gy][gx];
        if (gy == 0) path.moveTo(p.dx, p.dy); else path.lineTo(p.dx, p.dy);
      }

      final t = gx / _gridW;
      final amp = _smoothBand(audioData, gx, _gridW + 1);
      final alpha = (0.12 + amp * 0.45).clamp(0.08, 0.6);
      final hue = (HSLColor.fromColor(color).hue + t * 60 + time * 20 + 30) % 360;
      paint
        ..color = HSLColor.fromAHSL(alpha, hue, 0.8, 0.55).toColor()
        ..strokeWidth = 0.6 + amp * 1.5;
      canvas.drawPath(path, paint);
    }

    // Bright center flash on bass
    if (bass > 0.4) {
      final flashR = math.min(cx, cy) * bass * 0.3;
      canvas.drawCircle(Offset(cx, cy), flashR, Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy), flashR,
          [color.withValues(alpha: bass * 0.3), color.withValues(alpha: 0.0)],
        ));
    }
  }

  @override
  bool shouldRepaint(covariant MilkdropWarpVisualizer old) => true;
}

// ═════════════════════════════════════════════════════════════════════════════
// 15. FRACTAL FLAME — Simplified IFS with particle accumulation
// ═════════════════════════════════════════════════════════════════════════════

class FractalFlameVisualizer extends CustomPainter {
  final List<double> audioData;
  final Color color;
  final double time;

  static const int _iterations = 3000;

  FractalFlameVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = math.min(cx, cy) * 0.4;
    if (audioData.isEmpty) return;

    double bass = 0, mids = 0, treble = 0;
    final len = audioData.length;
    final q = math.max(1, len ~/ 3);
    for (int i = 0; i < q; i++) bass += audioData[i];
    for (int i = q; i < q * 2 && i < len; i++) mids += audioData[i];
    for (int i = q * 2; i < len; i++) treble += audioData[i];
    bass = (bass / q).clamp(0.0, 1.0);
    mids = (mids / q).clamp(0.0, 1.0);
    treble = (treble / math.max(1, len - q * 2)).clamp(0.0, 1.0);

    // IFS transforms — STRONGLY modulated by audio
    final bassAngle = bass * math.pi * 0.8;
    final midsAngle = time * math.pi * 2 + mids * math.pi;
    final transforms = <(double a, double b, double c, double d, double e, double f, double weight)>[
      // Scale + skew driven by bass
      (0.4 + bass * 0.4, bassAngle * 0.3, -bassAngle * 0.2, 0.4 + bass * 0.4, 0.5, bass * 0.3, 0.33),
      // Rotation driven by mids — speed and angle both react
      (
        0.5 * math.cos(midsAngle),
        -0.5 * math.sin(midsAngle),
        0.5 * math.sin(midsAngle),
        0.5 * math.cos(midsAngle),
        -0.4 - mids * 0.3, mids * 0.2, 0.33,
      ),
      // Spiral driven by treble — tighter spiral on loud treble
      (0.4 + treble * 0.3, -0.3 - treble * 0.5, 0.3 + treble * 0.5, 0.4 + treble * 0.3, treble * 0.3, 0.4, 0.34),
    ];

    // Compute cumulative weights
    final cumWeights = <double>[];
    double wSum = 0;
    for (final t in transforms) {
      wSum += t.$7;
      cumWeights.add(wSum);
    }

    final rng = math.Random(42 + (time * 10).floor());
    var px = rng.nextDouble() * 2 - 1;
    var py = rng.nextDouble() * 2 - 1;

    // Batch points by transform index for fewer draw calls
    final points = <List<Offset>>[[], [], []];

    for (int iter = 0; iter < _iterations; iter++) {
      final r = rng.nextDouble() * wSum;
      int ti = 0;
      while (ti < cumWeights.length - 1 && r > cumWeights[ti]) ti++;

      final (a, b, c, d, e, f, _) = transforms[ti];
      final nx = a * px + b * py + e;
      final ny = c * px + d * py + f;

      px = math.sin(nx);
      py = math.sin(ny);

      if (iter < 20) continue;

      final sx = cx + px * scale;
      final sy = cy + py * scale;
      if (sx < 0 || sx > size.width || sy < 0 || sy > size.height) continue;

      points[ti].add(Offset(sx, sy));
    }

    // Draw each batch with a single drawRawPoints call
    final baseHue = HSLColor.fromColor(color).hue;
    final alpha = (0.1 + bass * 0.15).clamp(0.05, 0.25);
    for (int ti = 0; ti < points.length; ti++) {
      if (points[ti].isEmpty) continue;
      final hue = (baseHue + ti * 80) % 360;
      final paint = Paint()
        ..color = HSLColor.fromAHSL(alpha, hue, 0.9, 0.6).toColor()
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      canvas.drawPoints(ui.PointMode.points, points[ti], paint);
    }

    // Additive center glow
    canvas.drawCircle(Offset(cx, cy), scale * 0.8, Paint()
      ..shader = ui.Gradient.radial(
        Offset(cx, cy), scale * 0.8,
        [color.withValues(alpha: 0.08 + bass * 0.08), color.withValues(alpha: 0.0)],
      ));
  }

  @override
  bool shouldRepaint(covariant FractalFlameVisualizer old) => true;
}
