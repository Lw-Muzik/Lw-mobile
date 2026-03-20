import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// 1. RADIAL BURST — Lines radiating from a center ring, length = amplitude
//    (Image 1 & 2 — the circular spiky visualizer)
// ═══════════════════════════════════════════════════════════════════════════════

class RadialBurstVisualizer extends CustomPainter {
  final List<double> audioData;
  final Color color;
  final double time;

  RadialBurstVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = math.min(cx, cy);
    final innerR = maxR * 0.22;
    final barCount = math.min(audioData.length, 180);
    if (barCount == 0) return;

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (int i = 0; i < barCount; i++) {
      final angle = (i / barCount) * math.pi * 2 - math.pi / 2;
      final amp = audioData[(i * audioData.length ~/ barCount)
          .clamp(0, audioData.length - 1)]
          .clamp(0.0, 1.0);

      final barLen = amp * maxR * 0.6 + maxR * 0.03;
      // Thicker bars for louder frequencies
      final thickness = 1.2 + amp * 2.5;

      final cosA = math.cos(angle);
      final sinA = math.sin(angle);

      final x1 = cx + cosA * innerR;
      final y1 = cy + sinA * innerR;
      final x2 = cx + cosA * (innerR + barLen);
      final y2 = cy + sinA * (innerR + barLen);

      paint
        ..color = color.withValues(alpha: 0.4 + amp * 0.6)
        ..strokeWidth = thickness;

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }

    // Inner circle ring
    canvas.drawCircle(
      Offset(cx, cy),
      innerR,
      Paint()
        ..color = color.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  @override
  bool shouldRepaint(covariant RadialBurstVisualizer old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 2. MIRROR BARS — Bars grow up AND down from center line
//    (Image 3, row 3 left — mirrored equalizer bars)
// ═══════════════════════════════════════════════════════════════════════════════

class MirrorBarsVisualizer extends CustomPainter {
  final List<double> audioData;
  final Color color;
  final double time;

  MirrorBarsVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final midY = h / 2;
    const barCount = 56;
    final barW = w / barCount;
    const gap = 1.5;
    if (audioData.isEmpty) return;

    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < barCount; i++) {
      final idx = (i * audioData.length / barCount).floor()
          .clamp(0, audioData.length - 1);
      final amp = audioData[idx].clamp(0.0, 1.0);
      final barH = amp * midY * 0.88;
      final x = i * barW + gap / 2;
      final bw = barW - gap;
      if (bw <= 0) continue;

      paint.color = color.withValues(alpha: 0.5 + amp * 0.5);

      // Up from center
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, midY - barH, bw, barH),
          const Radius.circular(1.5),
        ),
        paint,
      );
      // Down from center (mirror)
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, midY, bw, barH),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  @override
  bool shouldRepaint(covariant MirrorBarsVisualizer old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 3. WAVEFORM LINE — Smooth oscilloscope-style wave
//    (Image 3, row 1 left & row 2 left — clean sine-like waveform)
// ═══════════════════════════════════════════════════════════════════════════════

class WaveformLineVisualizer extends CustomPainter {
  final List<double> audioData;
  final Color color;
  final double time;

  WaveformLineVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final midY = h / 2;
    final count = math.min(audioData.length, 200);
    if (count < 2) return;

    // Glow behind main line
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final path = _buildSmoothPath(w, midY, h, count);
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, linePaint);

    // Faint center line
    canvas.drawLine(
      Offset(0, midY),
      Offset(w, midY),
      Paint()
        ..color = color.withValues(alpha: 0.06)
        ..strokeWidth = 0.5,
    );
  }

  Path _buildSmoothPath(double w, double midY, double h, int count) {
    final path = Path();
    final dx = w / (count - 1);
    final points = <Offset>[];

    for (int i = 0; i < count; i++) {
      final idx = (i * audioData.length / count).floor()
          .clamp(0, audioData.length - 1);
      final amp = (audioData[idx] - 0.5) * 2.0; // Center around 0
      final y = midY - amp * h * 0.35;
      points.add(Offset(i * dx, y));
    }

    // Catmull-Rom spline for smoothness
    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;

      final cp1x = p1.dx + (p2.dx - p0.dx) / 6;
      final cp1y = p1.dy + (p2.dy - p0.dy) / 6;
      final cp2x = p2.dx - (p3.dx - p1.dx) / 6;
      final cp2y = p2.dy - (p3.dy - p1.dy) / 6;

      path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  @override
  bool shouldRepaint(covariant WaveformLineVisualizer old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 4. TERRAIN / MOUNTAIN — Filled waveform like a mountain silhouette
//    (Image 3, row 2 right & row 3 center — mountain peaks)
// ═══════════════════════════════════════════════════════════════════════════════

class TerrainVisualizer extends CustomPainter {
  final List<double> audioData;
  final Color color;
  final double time;

  TerrainVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final count = math.min(audioData.length, 128);
    if (count < 2) return;

    // Build smooth mountain profile
    final points = <Offset>[];
    final dx = w / (count - 1);
    for (int i = 0; i < count; i++) {
      final idx = (i * audioData.length / count).floor()
          .clamp(0, audioData.length - 1);
      final amp = audioData[idx].clamp(0.0, 1.0);
      final y = h - amp * h * 0.85;
      points.add(Offset(i * dx, y));
    }

    // Catmull-Rom spline
    final curvePath = Path();
    curvePath.moveTo(0, h); // Start at bottom-left
    curvePath.lineTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;

      final cp1x = p1.dx + (p2.dx - p0.dx) / 6;
      final cp1y = p1.dy + (p2.dy - p0.dy) / 6;
      final cp2x = p2.dx - (p3.dx - p1.dx) / 6;
      final cp2y = p2.dy - (p3.dy - p1.dy) / 6;

      curvePath.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
    }

    curvePath.lineTo(w, h); // Bottom-right
    curvePath.close();

    // Gradient fill
    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(w / 2, 0),
        Offset(w / 2, h),
        [color.withValues(alpha: 0.5), color.withValues(alpha: 0.05)],
      );
    canvas.drawPath(curvePath, fillPaint);

    // Outline stroke
    // Rebuild just the top curve (without the bottom close)
    final strokePath = Path();
    strokePath.moveTo(points[0].dx, points[0].dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;
      strokePath.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx, p2.dy,
      );
    }

    canvas.drawPath(
      strokePath,
      Paint()
        ..color = color.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..isAntiAlias = true,
    );
  }

  @override
  @override
  bool shouldRepaint(covariant TerrainVisualizer old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 5. DOT MATRIX — Grid of dots whose size varies with amplitude
//    (Image 3, row 1 right — dotted spectrum grid)
// ═══════════════════════════════════════════════════════════════════════════════

class DotMatrixVisualizer extends CustomPainter {
  final List<double> audioData;
  final Color color;
  final double time;

  DotMatrixVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const cols = 32;
    const rows = 16;
    final cellW = w / cols;
    final cellH = h / rows;
    if (audioData.isEmpty) return;

    final paint = Paint()..isAntiAlias = true;

    for (int col = 0; col < cols; col++) {
      final idx = (col * audioData.length / cols).floor()
          .clamp(0, audioData.length - 1);
      final amp = audioData[idx].clamp(0.0, 1.0);
      // How many rows to light up from the bottom
      final litRows = (amp * rows).ceil();

      for (int row = 0; row < rows; row++) {
        final fromBottom = rows - 1 - row;
        final lit = fromBottom < litRows;
        final cx = col * cellW + cellW / 2;
        final cy = row * cellH + cellH / 2;
        final maxR = math.min(cellW, cellH) * 0.35;

        if (lit) {
          final intensity = 1.0 - (fromBottom / rows) * 0.4;
          paint.color = color.withValues(alpha: intensity * 0.8);
          canvas.drawCircle(Offset(cx, cy), maxR * (0.5 + amp * 0.5), paint);
        } else {
          paint.color = color.withValues(alpha: 0.06);
          canvas.drawCircle(Offset(cx, cy), maxR * 0.3, paint);
        }
      }
    }
  }

  @override
  @override
  bool shouldRepaint(covariant DotMatrixVisualizer old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 6. HELIX — Dual intertwined sine waves (3D-ish DNA/helix effect)
//    (Image 3, row 5 center — intertwined waves)
// ═══════════════════════════════════════════════════════════════════════════════

class HelixVisualizer extends CustomPainter {
  final List<double> audioData;
  final Color color;
  final double time;

  HelixVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final midY = h / 2;
    if (audioData.isEmpty) return;

    // Average amplitude for global size modulation
    double avgAmp = 0;
    final sampleCount = math.min(audioData.length, 64);
    for (int i = 0; i < sampleCount; i++) avgAmp += audioData[i];
    avgAmp = (avgAmp / sampleCount).clamp(0.0, 1.0);

    final steps = 200;
    final phase = time * math.pi * 2;

    for (int strand = 0; strand < 2; strand++) {
      final strandPhase = phase + strand * math.pi;
      final path = Path();
      final alphaBase = strand == 0 ? 0.7 : 0.4;

      for (int i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = t * w;
        final dataIdx = (t * math.min(audioData.length, 128))
            .floor().clamp(0, audioData.length - 1);
        final localAmp = audioData[dataIdx].clamp(0.0, 1.0);

        final envelope = (0.5 + localAmp * 0.5) * h * 0.3;
        final y = midY + math.sin(t * 6 * math.pi + strandPhase) * envelope;

        if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
      }

      // Draw connecting spheres at crossover points
      final paint = Paint()
        ..color = color.withValues(alpha: alphaBase)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strand == 0 ? 2.0 : 1.5
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawPath(path, paint);
    }

    // Draw nodes at crossover points
    final nodePaint = Paint()..isAntiAlias = true;
    for (int i = 0; i < 8; i++) {
      final t = (i + 0.5) / 8;
      final x = t * w;
      final dataIdx = (t * math.min(audioData.length, 64))
          .floor().clamp(0, audioData.length - 1);
      final amp = audioData[dataIdx].clamp(0.0, 1.0);
      final r = 3.0 + amp * 6.0;

      nodePaint.color = color.withValues(alpha: 0.5 + amp * 0.5);
      canvas.drawCircle(Offset(x, midY), r, nodePaint);
      // Glow
      nodePaint.color = color.withValues(alpha: 0.1 + amp * 0.15);
      canvas.drawCircle(Offset(x, midY), r * 2.5, nodePaint);
    }
  }

  @override
  @override
  bool shouldRepaint(covariant HelixVisualizer old) => true;
}
