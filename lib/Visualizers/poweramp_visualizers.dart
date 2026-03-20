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

  static const int _barCount = 120;

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
    if (audioData.isEmpty) return;

    // Bass energy: average the lowest 10% of frequency bands
    final bassCount = math.max(1, (audioData.length * 0.1).round());
    double bassEnergy = 0;
    for (int i = 0; i < bassCount; i++) {
      bassEnergy += audioData[i];
    }
    bassEnergy = (bassEnergy / bassCount).clamp(0.0, 1.0);

    // Inner radius pulses gently with bass
    final baseInnerR = maxR * 0.18;
    final innerR = baseInnerR + bassEnergy * maxR * 0.08;
    final maxBarLen = maxR * 0.75;

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (int i = 0; i < _barCount; i++) {
      final angle = (i / _barCount) * math.pi * 2 - math.pi / 2;

      // Logarithmic frequency mapping — bass bars on left, treble on right
      final t = i / _barCount;
      final logIdx = math.pow(t, 1.6) * audioData.length;
      final dataIdx = logIdx.floor().clamp(0, audioData.length - 1);

      // Average neighbors for smoothness
      double amp = 0;
      int count = 0;
      final spread = math.max(1, (audioData.length / _barCount * 0.5).round());
      for (int j = -spread; j <= spread; j++) {
        final idx = (dataIdx + j).clamp(0, audioData.length - 1);
        amp += audioData[idx];
        count++;
      }
      amp = (amp / count).clamp(0.0, 1.0);

      // Bass boost for low-frequency bars
      final bassBoost = (1.0 - t) * 0.35;
      final boosted = (amp * (1.0 + bassBoost)).clamp(0.0, 1.0);

      final barLen = boosted * maxBarLen + maxR * 0.02;
      final thickness = 1.0 + boosted * 2.0;

      final cosA = math.cos(angle);
      final sinA = math.sin(angle);

      paint
        ..color = color.withValues(alpha: 0.35 + boosted * 0.65)
        ..strokeWidth = thickness;

      canvas.drawLine(
        Offset(cx + cosA * innerR, cy + sinA * innerR),
        Offset(cx + cosA * (innerR + barLen), cy + sinA * (innerR + barLen)),
        paint,
      );
    }

    // Inner circle ring — glows brighter on bass hits
    canvas.drawCircle(
      Offset(cx, cy),
      innerR,
      Paint()
        ..color = color.withValues(alpha: 0.2 + bassEnergy * 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 + bassEnergy * 1.5,
    );
  }

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

  static const int _barCount = 56;

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
    final barW = w / _barCount;
    const gap = 1.5;
    if (audioData.isEmpty) return;

    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < _barCount; i++) {
      // Logarithmic frequency mapping
      final t = i / _barCount;
      final logIdx = math.pow(t, 1.8) * audioData.length;
      final dataIdx = logIdx.floor().clamp(0, audioData.length - 1);

      // Average neighbors
      double amp = 0;
      int count = 0;
      final spread = math.max(1, (audioData.length / _barCount * 0.5).round());
      for (int j = -spread; j <= spread; j++) {
        final idx = (dataIdx + j).clamp(0, audioData.length - 1);
        amp += audioData[idx];
        count++;
      }
      amp = (amp / count).clamp(0.0, 1.0);

      // Bass boost
      final bassBoost = (1.0 - t) * 0.35;
      final boosted = (amp * (1.0 + bassBoost)).clamp(0.0, 1.0);

      // Bars use 90% of half-height
      final barH = boosted * midY * 0.9;
      final x = i * barW + gap / 2;
      final bw = barW - gap;
      if (bw <= 0) continue;

      paint.color = color.withValues(alpha: 0.45 + boosted * 0.55);

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
      final amp = audioData[idx].clamp(-1.0, 1.0); // Already signed -1..1
      final y = midY - amp * h * 0.4;
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

  static const int _cols = 32;
  static const int _rows = 20;

  DotMatrixVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cellW = w / _cols;
    final cellH = h / _rows;
    if (audioData.isEmpty) return;

    final paint = Paint()..isAntiAlias = true;

    for (int col = 0; col < _cols; col++) {
      // Logarithmic frequency mapping — same as spectrum
      final t = col / _cols;
      final logIdx = math.pow(t, 1.8) * audioData.length;
      final dataIdx = logIdx.floor().clamp(0, audioData.length - 1);

      // Average neighbors
      double amp = 0;
      int count = 0;
      final spread = math.max(1, (audioData.length / _cols * 0.5).round());
      for (int j = -spread; j <= spread; j++) {
        final idx = (dataIdx + j).clamp(0, audioData.length - 1);
        amp += audioData[idx];
        count++;
      }
      amp = (amp / count).clamp(0.0, 1.0);

      // Bass boost
      final bassBoost = (1.0 - t) * 0.35;
      final boosted = (amp * (1.0 + bassBoost)).clamp(0.0, 1.0);

      // How many rows to light from the bottom
      final litRows = (boosted * _rows).ceil();

      for (int row = 0; row < _rows; row++) {
        final fromBottom = _rows - 1 - row;
        final lit = fromBottom < litRows;
        final dotX = col * cellW + cellW / 2;
        final dotY = row * cellH + cellH / 2;
        final maxR = math.min(cellW, cellH) * 0.35;

        if (lit) {
          // Higher dots (closer to peak) glow brighter
          final peakProximity = 1.0 - (litRows > 0 ? fromBottom / litRows : 0.0).clamp(0.0, 1.0);
          paint.color = color.withValues(alpha: 0.4 + peakProximity * 0.6);
          canvas.drawCircle(Offset(dotX, dotY), maxR * (0.6 + boosted * 0.4), paint);
        } else {
          paint.color = color.withValues(alpha: 0.05);
          canvas.drawCircle(Offset(dotX, dotY), maxR * 0.25, paint);
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
  bool shouldRepaint(covariant HelixVisualizer old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 7. SILK WAVES — Multiple layered waveform lines with phase offsets
//    creating a 3D ribbon/silk effect (Image 1)
// ═══════════════════════════════════════════════════════════════════════════════

class SilkWavesVisualizer extends CustomPainter {
  final List<double> audioData; // signed waveform -1..1
  final Color color;
  final double time;

  static const int _layers = 20;
  static const int _points = 150;

  SilkWavesVisualizer({
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

    for (int layer = 0; layer < _layers; layer++) {
      final t = layer / _layers;
      final ampScale = 0.6 + (1.0 - (t - 0.5).abs() * 2) * 0.4;
      // Brighter at center layers, still visible at edges
      final alpha = (0.15 + (1.0 - (t - 0.5).abs() * 2) * 0.55).clamp(0.1, 0.7);

      final paint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..isAntiAlias = true;

      final path = Path();
      for (int i = 0; i <= _points; i++) {
        final x = i / _points;
        // Offset each layer's data read for visual separation
        final dataOffset = (t * audioData.length * 0.15).floor();
        final dataIdx = ((x * audioData.length).floor() + dataOffset)
            .clamp(0, audioData.length - 1);
        final amp = audioData[dataIdx].clamp(-1.0, 1.0);

        // Envelope: taper to zero at edges
        final envelope = math.sin(x * math.pi);
        final yOffset = amp * ampScale * envelope * h * 0.45;
        // Spread layers vertically for ribbon depth
        final spread = (t - 0.5) * 2.0 * h * 0.15;
        final y = midY + yOffset + spread;
        final px = x * w;

        if (i == 0) path.moveTo(px, y); else path.lineTo(px, y);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SilkWavesVisualizer old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 8. LISSAJOUS — Layered closed curves that twist with audio (Image 2)
// ═══════════════════════════════════════════════════════════════════════════════

class LissajousVisualizer extends CustomPainter {
  final List<double> audioData; // freq bands 0..1
  final Color color;
  final double time;

  static const int _layers = 24;
  static const int _pointsPerCurve = 200;

  LissajousVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = math.min(cx, cy) * 0.7;
    if (audioData.isEmpty) return;

    // Global audio energy drives overall size
    double energy = 0;
    for (int i = 0; i < math.min(audioData.length, 32); i++) energy += audioData[i];
    energy = (energy / 32).clamp(0.0, 1.0);

    final phase = time * math.pi * 2;

    for (int layer = 0; layer < _layers; layer++) {
      final t = layer / _layers;
      final layerPhase = phase + t * math.pi * 0.5;
      final radius = maxR * (0.3 + energy * 0.7) * (0.4 + t * 0.6);

      // Frequency ratios for Lissajous — slightly detuned for organic feel
      final freqA = 2.0 + energy * 1.5;
      final freqB = 3.0 + energy * 0.8;

      // Per-layer audio modulation from different freq bands
      final bandIdx = (t * audioData.length).floor().clamp(0, audioData.length - 1);
      final bandAmp = audioData[bandIdx].clamp(0.0, 1.0);

      final alpha = (0.15 + bandAmp * 0.45).clamp(0.1, 0.6);
      // Color shift across layers
      final hue = (color.computeLuminance() > 0.5 ? 340.0 : 0.0) + t * 60;
      final layerColor = HSLColor.fromAHSL(alpha, hue % 360, 0.8, 0.6).toColor();

      final paint = Paint()
        ..color = layerColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..isAntiAlias = true;

      final path = Path();
      for (int i = 0; i <= _pointsPerCurve; i++) {
        final u = i / _pointsPerCurve * math.pi * 2;
        final x = cx + radius * math.sin(freqA * u + layerPhase) * (1.0 + bandAmp * 0.3);
        final y = cy + radius * math.cos(freqB * u + layerPhase * 0.7) * (1.0 + bandAmp * 0.3);

        if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant LissajousVisualizer old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 9. WINDMILL — Radial arc segments fanning from center (Image 3)
// ═══════════════════════════════════════════════════════════════════════════════

class WindmillVisualizer extends CustomPainter {
  final List<double> audioData; // freq bands 0..1
  final Color color;
  final double time;

  static const int _blades = 8;
  static const int _arcsPerBlade = 20;

  WindmillVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = math.min(cx, cy) * 0.85;
    final innerR = maxR * 0.1;
    if (audioData.isEmpty) return;

    final rotation = time * math.pi * 2 * 0.3;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    for (int blade = 0; blade < _blades; blade++) {
      final bladeAngle = (blade / _blades) * math.pi * 2 + rotation;

      // Each blade's amplitude from a different freq band (log-mapped)
      final t = blade / _blades;
      final logIdx = math.pow(t, 1.5) * audioData.length;
      final bandIdx = logIdx.floor().clamp(0, audioData.length - 1);
      final bladeAmp = audioData[bandIdx].clamp(0.0, 1.0);

      // Sweep angle driven by amplitude — bigger sweep for louder bands
      final sweepAngle = (0.15 + bladeAmp * 0.6) * (math.pi * 2 / _blades);

      for (int arc = 0; arc < _arcsPerBlade; arc++) {
        final at = arc / _arcsPerBlade;
        final r = innerR + at * (maxR - innerR) * (0.4 + bladeAmp * 0.6);
        // Much more visible: bright at inner arcs, fade outward
        final alpha = (0.2 + (1.0 - at) * 0.5 * (0.3 + bladeAmp * 0.7)).clamp(0.05, 0.7);

        paint
          ..color = color.withValues(alpha: alpha)
          ..strokeWidth = 1.2 + bladeAmp * 1.0;

        canvas.drawArc(
          Rect.fromCircle(center: Offset(cx, cy), radius: r),
          bladeAngle - sweepAngle / 2,
          sweepAngle,
          false,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant WindmillVisualizer old) => true;
}
