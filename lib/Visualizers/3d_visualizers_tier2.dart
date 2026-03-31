import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Shared helpers
// ═════════════════════════════════════════════════════════════════════════════

const double _focal = 300.0;

Offset _proj(double x, double y, double z, double cx, double cy) {
  final s = _focal / (z + _focal);
  return Offset(x * s + cx, y * s + cy);
}

double _pScale(double z) => _focal / (z + _focal);

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

(double, double, double) _rotY(double x, double y, double z, double a) {
  final c = math.cos(a), s = math.sin(a);
  return (x * c + z * s, y, -x * s + z * c);
}

(double, double, double) _rotX(double x, double y, double z, double a) {
  final c = math.cos(a), s = math.sin(a);
  return (x, y * c - z * s, y * s + z * c);
}

void _drawGlow(Canvas canvas, Path path, Color color, double width) {
  final style = PaintingStyle.stroke;
  canvas.drawPath(path, Paint()
    ..color = color.withValues(alpha: 0.15)
    ..style = style..strokeWidth = width * 3
    ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
  canvas.drawPath(path, Paint()
    ..color = color.withValues(alpha: 0.9)
    ..style = style..strokeWidth = width
    ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
}

// ═════════════════════════════════════════════════════════════════════════════
// 8. AUDIO TERRAIN — 3D wireframe landscape with cross-grid, height = FFT
//    Top-down tilted view, scrolling forward, strong bass mountains
// ═════════════════════════════════════════════════════════════════════════════

class AudioTerrainVisualizer extends CustomPainter {
  final List<double> audioData;
  final List<List<double>> fftHistory;
  final Color color;
  final double time;

  static const int _cols = 40;
  static const int _rows = 24;

  AudioTerrainVisualizer({
    required this.audioData,
    required this.fftHistory,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.6;
    if (audioData.isEmpty && fftHistory.isEmpty) return;

    final tiltX = 0.85;
    final rotAngle = math.pi * 0.05;

    // Build projected grid points
    final grid = List.generate(_rows + 1, (row) {
      final histIdx = row < fftHistory.length ? row : 0;
      final rowData = histIdx < fftHistory.length ? fftHistory[histIdx] : audioData;
      final depth = row / _rows;

      return List.generate(_cols + 1, (col) {
        final xFrac = (col / _cols) * 2.0 - 1.0;
        final amp = _smoothBand(rowData, col, _cols + 1);

        // Strong height — bass bands get extra boost
        final bassBoost = col < _cols ~/ 4 ? 1.4 : 1.0;
        final height = amp * 180 * bassBoost;

        var x = xFrac * size.width * 0.55;
        var y = -height;
        var z = depth * 350 + 60;

        (x, y, z) = _rotY(x, y, z, rotAngle);
        (x, y, z) = _rotX(x, y, z, tiltX);

        return (proj: _proj(x, y, z, cx, cy), amp: amp, depth: depth);
      });
    });

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    // Draw horizontal lines (frequency axis) — back to front
    for (int row = _rows; row >= 0; row--) {
      final path = Path();
      double rowMaxAmp = 0;
      for (int col = 0; col <= _cols; col++) {
        final pt = grid[row][col];
        if (col == 0) {
          path.moveTo(pt.proj.dx, pt.proj.dy);
        } else {
          path.lineTo(pt.proj.dx, pt.proj.dy);
        }
        if (pt.amp > rowMaxAmp) rowMaxAmp = pt.amp;
      }

      final depth = grid[row][0].depth;
      final alpha = ((1.0 - depth) * 0.65 + rowMaxAmp * 0.25 + 0.1).clamp(0.08, 0.8);

      paint
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = (1.5 * (1.0 - depth * 0.4) + rowMaxAmp * 1.0).clamp(0.5, 2.5);
      canvas.drawPath(path, paint);
    }

    // Draw vertical lines (time axis) — every 3rd column for wireframe look
    for (int col = 0; col <= _cols; col += 3) {
      final path = Path();
      for (int row = 0; row <= _rows; row++) {
        final pt = grid[row][col];
        if (row == 0) {
          path.moveTo(pt.proj.dx, pt.proj.dy);
        } else {
          path.lineTo(pt.proj.dx, pt.proj.dy);
        }
      }

      final colAmp = _smoothBand(audioData, col, _cols + 1);
      final alpha = (0.08 + colAmp * 0.25).clamp(0.05, 0.35);
      paint
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = 0.6 + colAmp * 0.5;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant AudioTerrainVisualizer old) => true;
}

// ═════════════════════════════════════════════════════════════════════════════
// 9. MESH SPHERE — Spiky ball with strong FFT vertex displacement
// ═════════════════════════════════════════════════════════════════════════════

class MeshSphereVisualizer extends CustomPainter {
  final List<double> audioData;
  final Color color;
  final double time;

  MeshSphereVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseR = math.min(cx, cy) * 0.28;
    if (audioData.isEmpty) return;

    // Overall energy drives base scale pulsing
    double energy = 0;
    for (int i = 0; i < math.min(audioData.length, 32); i++) energy += audioData[i];
    energy = (energy / 32).clamp(0.0, 1.0);

    final rotYAngle = time * math.pi * 2 * 0.25;
    final rotXAngle = math.pi * 0.2 + math.sin(time * math.pi * 2 * 0.15) * 0.15;

    final latDiv = 12;
    final lonDiv = 18;
    final edges = <(double z, Offset a, Offset b, double amp)>[];

    for (int lat = 0; lat <= latDiv; lat++) {
      for (int lon = 0; lon < lonDiv; lon++) {
        final phi1 = (lat / latDiv) * math.pi;
        final phi2 = ((lat + 1).clamp(0, latDiv) / latDiv) * math.pi;
        final theta1 = (lon / lonDiv) * math.pi * 2;
        final theta2 = ((lon + 1) % lonDiv / lonDiv) * math.pi * 2;

        // Map lat to bass bands, lon to full spectrum — strong displacement
        final bandLat = _band(audioData, lat, latDiv + 1);
        final bandLon = _band(audioData, lon, lonDiv);
        final amp = ((bandLat + bandLon) / 2).clamp(0.0, 1.0);
        // 1.0 base + up to 1.2 extra from audio + 0.3 from global energy
        final displacement = 1.0 + amp * 1.2 + energy * 0.3;

        final r1 = baseR * displacement;

        var x1 = math.sin(phi1) * math.cos(theta1) * r1;
        var y1 = math.cos(phi1) * r1;
        var z1 = math.sin(phi1) * math.sin(theta1) * r1;
        (x1, y1, z1) = _rotY(x1, y1, z1, rotYAngle);
        (x1, y1, z1) = _rotX(x1, y1, z1, rotXAngle);

        // Horizontal neighbor
        final ampH = _band(audioData, (lon + 1) % lonDiv, lonDiv);
        final rH = baseR * (1.0 + ampH * 1.2 + energy * 0.3);
        var x2 = math.sin(phi1) * math.cos(theta2) * rH;
        var y2 = math.cos(phi1) * rH;
        var z2 = math.sin(phi1) * math.sin(theta2) * rH;
        (x2, y2, z2) = _rotY(x2, y2, z2, rotYAngle);
        (x2, y2, z2) = _rotX(x2, y2, z2, rotXAngle);

        // Vertical neighbor
        final ampV = _band(audioData, (lat + 1).clamp(0, latDiv), latDiv + 1);
        final rV = baseR * (1.0 + ampV * 1.2 + energy * 0.3);
        var x3 = math.sin(phi2) * math.cos(theta1) * rV;
        var y3 = math.cos(phi2) * rV;
        var z3 = math.sin(phi2) * math.sin(theta1) * rV;
        (x3, y3, z3) = _rotY(x3, y3, z3, rotYAngle);
        (x3, y3, z3) = _rotX(x3, y3, z3, rotXAngle);

        final p1 = _proj(x1, y1, z1, cx, cy);
        final p2 = _proj(x2, y2, z2, cx, cy);
        final p3 = _proj(x3, y3, z3, cx, cy);

        edges.add(((z1 + z2) / 2, p1, p2, amp));
        if (lat < latDiv) {
          edges.add(((z1 + z3) / 2, p1, p3, amp));
        }
      }
    }

    edges.sort((a, b) => a.$1.compareTo(b.$1));

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (final (z, a, b, amp) in edges) {
      final depthAlpha = (0.2 + _pScale(z) * 0.8).clamp(0.1, 1.0);
      // Bright on loud, dim on quiet — strong contrast
      paint
        ..color = color.withValues(alpha: (0.15 + amp * 0.75) * depthAlpha)
        ..strokeWidth = (0.6 + amp * 2.5) * _pScale(z);
      canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(covariant MeshSphereVisualizer old) => true;
}

// ═════════════════════════════════════════════════════════════════════════════
// 10. MORPHING ORB — Dramatic pulsing sphere with strong harmonic distortion
// ═════════════════════════════════════════════════════════════════════════════

class MorphingOrbVisualizer extends CustomPainter {
  final List<double> audioData;
  final Color color;
  final double time;

  MorphingOrbVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseR = math.min(cx, cy) * 0.32;
    if (audioData.isEmpty) return;

    // Separate bass/mids/treble with strong influence
    double bass = 0, mids = 0, treble = 0;
    final len = audioData.length;
    final bassEnd = len ~/ 4;
    final midsEnd = len ~/ 2;
    for (int i = 0; i < bassEnd; i++) bass += audioData[i];
    for (int i = bassEnd; i < midsEnd; i++) mids += audioData[i];
    for (int i = midsEnd; i < len; i++) treble += audioData[i];
    bass = (bass / bassEnd).clamp(0.0, 1.0);
    mids = (mids / (midsEnd - bassEnd)).clamp(0.0, 1.0);
    treble = (treble / (len - midsEnd)).clamp(0.0, 1.0);

    final phase = time * math.pi * 2;
    final rotAngle = time * 0.6;

    // Draw latitude rings with STRONG harmonic displacement
    final latSteps = 20;
    final lonSteps = 40;

    for (int lat = 1; lat < latSteps; lat++) {
      final phi = (lat / latSteps) * math.pi;
      final path = Path();

      for (int lon = 0; lon <= lonSteps; lon++) {
        final theta = (lon / lonSteps) * math.pi * 2;

        // Per-vertex frequency band lookup for detailed response
        final vertBand = _band(audioData, lon, lonSteps + 1);

        // Strong spherical harmonics — 3x the original multipliers
        final d1 = bass * 0.7 * math.sin(phi * 2) * math.cos(theta * 2 + phase);
        final d2 = mids * 0.5 * math.sin(phi * 3) * math.cos(theta * 3 + phase * 1.5);
        final d3 = treble * 0.35 * math.sin(phi * 5) * math.cos(theta * 5 + phase * 2.5);
        // Per-vertex modulation for fine detail
        final d4 = vertBand * 0.3 * math.sin(phi * 4 + theta * 4);

        final r = baseR * (1.0 + d1 + d2 + d3 + d4);

        var x = math.sin(phi) * math.cos(theta) * r;
        var y = math.cos(phi) * r;
        var z = math.sin(phi) * math.sin(theta) * r;

        (x, y, z) = _rotY(x, y, z, rotAngle);
        (x, y, z) = _rotX(x, y, z, 0.35);

        final p = _proj(x, y, z, cx, cy);
        if (lon == 0) path.moveTo(p.dx, p.dy); else path.lineTo(p.dx, p.dy);
      }

      final latFrac = (lat / latSteps - 0.5).abs() * 2;
      final alpha = (0.15 + (1.0 - latFrac) * 0.4 + bass * 0.3).clamp(0.08, 0.75);

      canvas.drawPath(path, Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 + bass * 0.8
        ..isAntiAlias = true);
    }

    // Longitude lines — every 3rd, for wireframe depth
    for (int lon = 0; lon < lonSteps; lon += 3) {
      final theta = (lon / lonSteps) * math.pi * 2;
      final path = Path();

      for (int lat = 0; lat <= latSteps; lat++) {
        final phi = (lat / latSteps) * math.pi;
        final d1 = bass * 0.7 * math.sin(phi * 2) * math.cos(theta * 2 + phase);
        final d2 = mids * 0.5 * math.sin(phi * 3) * math.cos(theta * 3 + phase * 1.5);
        final r = baseR * (1.0 + d1 + d2);

        var x = math.sin(phi) * math.cos(theta) * r;
        var y = math.cos(phi) * r;
        var z = math.sin(phi) * math.sin(theta) * r;

        (x, y, z) = _rotY(x, y, z, rotAngle);
        (x, y, z) = _rotX(x, y, z, 0.35);

        final p = _proj(x, y, z, cx, cy);
        if (lat == 0) path.moveTo(p.dx, p.dy); else path.lineTo(p.dx, p.dy);
      }

      canvas.drawPath(path, Paint()
        ..color = color.withValues(alpha: 0.1 + mids * 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..isAntiAlias = true);
    }

    // Central glow that breathes with bass
    final glowR = baseR * (1.2 + bass * 0.6);
    canvas.drawCircle(Offset(cx, cy), glowR, Paint()
      ..shader = ui.Gradient.radial(
        Offset(cx, cy), glowR,
        [color.withValues(alpha: 0.12 + bass * 0.2), color.withValues(alpha: 0.0)],
      ));
  }

  @override
  bool shouldRepaint(covariant MorphingOrbVisualizer old) => true;
}

// ═════════════════════════════════════════════════════════════════════════════
// 11. REACTIVE GEOMETRY — Wireframe icosahedron with strong displacement
// ═════════════════════════════════════════════════════════════════════════════

class ReactiveGeometryVisualizer extends CustomPainter {
  final List<double> audioData;
  final Color color;
  final double time;

  ReactiveGeometryVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseR = math.min(cx, cy) * 0.3;
    if (audioData.isEmpty) return;

    double energy = 0;
    for (int i = 0; i < math.min(audioData.length, 32); i++) energy += audioData[i];
    energy = (energy / 32).clamp(0.0, 1.0);

    final rotYA = time * math.pi * 2 * 0.2;
    final rotXA = time * math.pi * 2 * 0.12 + energy * 0.3;

    final phi = (1.0 + math.sqrt(5)) / 2.0;
    final rawVerts = <(double, double, double)>[
      (-1,  phi, 0), ( 1,  phi, 0), (-1, -phi, 0), ( 1, -phi, 0),
      ( 0, -1,  phi), ( 0,  1,  phi), ( 0, -1, -phi), ( 0,  1, -phi),
      ( phi, 0, -1), ( phi, 0,  1), (-phi, 0, -1), (-phi, 0,  1),
    ];

    final norm = math.sqrt(1 + phi * phi);
    final verts = rawVerts.map((v) => (v.$1 / norm, v.$2 / norm, v.$3 / norm)).toList();

    const faces = [
      [0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],
      [1,5,9],[5,11,4],[11,10,2],[10,7,6],[7,1,8],
      [3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],
      [4,9,5],[2,4,11],[6,2,10],[8,6,7],[9,8,1],
    ];

    final edgeSet = <int>{};
    final edgeList = <(int, int)>[];
    for (final f in faces) {
      for (int i = 0; i < 3; i++) {
        final a = f[i], b = f[(i + 1) % 3];
        final a0 = a < b ? a : b;
        final b0 = a < b ? b : a;
        final key = a0 * 100 + b0;
        if (edgeSet.add(key)) edgeList.add((a, b));
      }
    }

    // Strong displacement — up to 2x base radius on loud hits
    final projected = <Offset>[];
    final zValues = <double>[];
    final ampValues = <double>[];
    for (int i = 0; i < verts.length; i++) {
      final amp = _band(audioData, i, verts.length);
      ampValues.add(amp);
      final displacement = 1.0 + amp * 1.0 + energy * 0.4;
      var x = verts[i].$1 * baseR * displacement;
      var y = verts[i].$2 * baseR * displacement;
      var z = verts[i].$3 * baseR * displacement;

      (x, y, z) = _rotY(x, y, z, rotYA);
      (x, y, z) = _rotX(x, y, z, rotXA);

      projected.add(_proj(x, y, z, cx, cy));
      zValues.add(z);
    }

    final sortedEdges = List.generate(edgeList.length, (i) => i);
    sortedEdges.sort((a, b) {
      final za = (zValues[edgeList[a].$1] + zValues[edgeList[a].$2]) / 2;
      final zb = (zValues[edgeList[b].$1] + zValues[edgeList[b].$2]) / 2;
      return za.compareTo(zb);
    });

    for (final ei in sortedEdges) {
      final (a, b) = edgeList[ei];
      final avgZ = (zValues[a] + zValues[b]) / 2;
      final depthAlpha = (0.3 + _pScale(avgZ) * 0.7).clamp(0.2, 1.0);
      final amp = (ampValues[a] + ampValues[b]) / 2;
      final width = 1.2 + amp * 3.0;

      _drawGlow(
        canvas,
        Path()..moveTo(projected[a].dx, projected[a].dy)..lineTo(projected[b].dx, projected[b].dy),
        color.withValues(alpha: depthAlpha * (0.4 + amp * 0.6)),
        width * _pScale(avgZ),
      );
    }

    // Vertex dots — bigger on loud bands
    final dotPaint = Paint()..isAntiAlias = true;
    for (int i = 0; i < verts.length; i++) {
      final amp = ampValues[i];
      final r = (3.0 + amp * 6.0) * _pScale(zValues[i]);
      dotPaint.color = color.withValues(alpha: (0.4 + amp * 0.6).clamp(0.0, 1.0));
      canvas.drawCircle(projected[i], r, dotPaint);
      // Glow on loud vertices
      if (amp > 0.4) {
        dotPaint.color = color.withValues(alpha: amp * 0.2);
        canvas.drawCircle(projected[i], r * 3, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ReactiveGeometryVisualizer old) => true;
}

// ═════════════════════════════════════════════════════════════════════════════
// 12. 3D WATERFALL SPECTROGRAM — Side-view scrolling heat columns
//     FUNDAMENTALLY DIFFERENT from terrain: vertical bars falling downward
//     like a waterfall, color intensity = amplitude, side perspective view
// ═════════════════════════════════════════════════════════════════════════════

class WaterfallSpectrogramVisualizer extends CustomPainter {
  final List<double> audioData;
  final List<List<double>> fftHistory;
  final Color color;
  final double time;

  static const int _freqBins = 40;
  static const int _timeSlices = 25;

  WaterfallSpectrogramVisualizer({
    required this.audioData,
    required this.fftHistory,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (fftHistory.isEmpty && audioData.isEmpty) return;

    final baseHue = HSLColor.fromColor(color).hue;
    final sliceCount = math.min(_timeSlices, math.max(fftHistory.length, 1));

    // Each time slice is a VERTICAL COLUMN of colored cells
    // X axis = time (left = oldest, right = newest)
    // Y axis = frequency (bottom = bass, top = treble)
    // Color intensity = amplitude
    final cellW = w / _timeSlices;
    final cellH = h / _freqBins;

    final paint = Paint()..style = PaintingStyle.fill;

    for (int t = 0; t < sliceCount; t++) {
      final data = t < fftHistory.length ? fftHistory[t] : audioData;
      // Newest on right, oldest on left
      final xBase = w - (t + 1) * cellW;
      final age = t / _timeSlices; // 0 = newest, 1 = oldest

      for (int f = 0; f < _freqBins; f++) {
        final amp = _smoothBand(data, f, _freqBins);
        if (amp < 0.02) continue; // skip silent cells

        // Y: low freq at bottom, high at top
        final yBase = h - (f + 1) * cellH;

        // Color: hue shifts with frequency, brightness with amplitude
        // Bass = warm (red/orange), Treble = cool (blue/purple)
        final freqFrac = f / _freqBins;
        final hue = (baseHue + freqFrac * 90) % 360;
        final lightness = (0.25 + amp * 0.45).clamp(0.2, 0.7);
        final sat = (0.6 + amp * 0.4).clamp(0.5, 1.0);
        final alpha = ((0.3 + amp * 0.7) * (1.0 - age * 0.6)).clamp(0.05, 0.95);

        paint.color = HSLColor.fromAHSL(alpha, hue, sat, lightness).toColor();

        canvas.drawRect(
          Rect.fromLTWH(xBase, yBase, cellW + 0.5, cellH + 0.5),
          paint,
        );
      }
    }

    // Overlay: current spectrum as bright line on the right edge
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..isAntiAlias = true;

    final specPath = Path();
    for (int f = 0; f < _freqBins; f++) {
      final amp = _smoothBand(audioData, f, _freqBins);
      final yPos = h - (f + 0.5) * cellH;
      final xPos = w - amp * cellW * 4; // bars extend leftward from right edge

      if (f == 0) {
        specPath.moveTo(xPos, yPos);
      } else {
        specPath.lineTo(xPos, yPos);
      }
    }

    linePaint.color = color.withValues(alpha: 0.8);
    canvas.drawPath(specPath, linePaint);
    // Glow
    linePaint
      ..color = color.withValues(alpha: 0.15)
      ..strokeWidth = 6.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(specPath, linePaint);

    // Frequency labels area — thin vertical separator
    canvas.drawLine(
      Offset(w - cellW * 0.3, 0),
      Offset(w - cellW * 0.3, h),
      Paint()..color = color.withValues(alpha: 0.1)..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(covariant WaterfallSpectrogramVisualizer old) => true;
}
