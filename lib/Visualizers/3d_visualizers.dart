import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Shared 3D projection helpers
// ═════════════════════════════════════════════════════════════════════════════

const double _focalLength = 300.0;

/// Perspective project a 3D point to 2D screen coords.
Offset _project(double x, double y, double z, double cx, double cy) {
  final scale = _focalLength / (z + _focalLength);
  return Offset(x * scale + cx, y * scale + cy);
}

double _projectScale(double z) => _focalLength / (z + _focalLength);

/// Read a frequency band value from pre-processed data.
double _band(List<double> data, int i, int total) {
  if (data.isEmpty) return 0.0;
  final idx = (i * data.length / total).floor().clamp(0, data.length - 1);
  return data[idx].clamp(0.0, 1.0);
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

/// Rotate a 3D point around the Y axis.
(double x, double y, double z) _rotateY(double x, double y, double z, double angle) {
  final c = math.cos(angle);
  final s = math.sin(angle);
  return (x * c + z * s, y, -x * s + z * c);
}

/// Rotate a 3D point around the X axis.
(double x, double y, double z) _rotateX(double x, double y, double z, double angle) {
  final c = math.cos(angle);
  final s = math.sin(angle);
  return (x, y * c - z * s, y * s + z * c);
}

/// Draw a line with neon glow effect.
void _drawGlowLine(Canvas canvas, Offset a, Offset b, Color color, double width) {
  // Outer glow
  canvas.drawLine(a, b, Paint()
    ..color = color.withValues(alpha: 0.08)
    ..strokeWidth = width * 4
    ..strokeCap = StrokeCap.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  // Mid glow
  canvas.drawLine(a, b, Paint()
    ..color = color.withValues(alpha: 0.25)
    ..strokeWidth = width * 2
    ..strokeCap = StrokeCap.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
  // Core
  canvas.drawLine(a, b, Paint()
    ..color = color.withValues(alpha: 0.9)
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round);
}

/// Draw a path with neon glow effect (2-pass: glow + core).
void _drawGlowPath(Canvas canvas, Path path, Color color, double width) {
  final style = PaintingStyle.stroke;
  canvas.drawPath(path, Paint()
    ..color = color.withValues(alpha: 0.15)
    ..style = style
    ..strokeWidth = width * 3
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
  canvas.drawPath(path, Paint()
    ..color = color.withValues(alpha: 0.9)
    ..style = style
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round);
}

// ═════════════════════════════════════════════════════════════════════════════
// 1. NEON GRID HORIZON — Synthwave Tron-style perspective grid
// ═════════════════════════════════════════════════════════════════════════════

class NeonGridHorizonVisualizer extends CustomPainter {
  final List<double> audioData;
  final Color color;
  final double time;

  static const int _gridLinesZ = 30;
  static const int _gridLinesX = 20;

  NeonGridHorizonVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final horizon = h * 0.35;
    if (audioData.isEmpty) return;

    // Bass energy for pulsing
    double bassEnergy = 0;
    final bassCount = math.max(1, (audioData.length * 0.1).round());
    for (int i = 0; i < bassCount; i++) bassEnergy += audioData[i];
    bassEnergy = (bassEnergy / bassCount).clamp(0.0, 1.0);

    final gridColor = color.withValues(alpha: 0.3 + bassEnergy * 0.4);

    // Scrolling offset
    final scrollZ = (time * 3.0) % 1.0;

    // Horizontal lines receding into distance
    for (int i = 0; i < _gridLinesZ; i++) {
      final t = (i + scrollZ) / _gridLinesZ;
      final perspY = horizon + (h - horizon) * t;
      final perspScale = t.clamp(0.05, 1.0);
      final alpha = (0.1 + perspScale * 0.6).clamp(0.0, 1.0);

      canvas.drawLine(
        Offset(cx - cx * perspScale * 1.5, perspY),
        Offset(cx + cx * perspScale * 1.5, perspY),
        Paint()
          ..color = gridColor.withValues(alpha: alpha)
          ..strokeWidth = 0.5 + perspScale * 1.0,
      );
    }

    // Vertical lines converging to vanishing point
    for (int i = 0; i < _gridLinesX; i++) {
      final t = (i / (_gridLinesX - 1)) * 2.0 - 1.0; // -1 to 1
      final topX = cx + t * w * 0.08;
      final botX = cx + t * cx * 1.5;

      canvas.drawLine(
        Offset(topX, horizon),
        Offset(botX, h),
        Paint()
          ..color = gridColor.withValues(alpha: 0.25)
          ..strokeWidth = 0.8,
      );
    }

    // Frequency pillars rising from grid
    final pillarCount = 32;
    for (int i = 0; i < pillarCount; i++) {
      final amp = _band(audioData, i, pillarCount);
      if (amp < 0.05) continue;

      final xPos = (i / (pillarCount - 1)) * 2.0 - 1.0;
      final zDepth = 0.3 + (i % 5) * 0.14;
      final perspY = horizon + (h - horizon) * zDepth;
      final perspScale = zDepth.clamp(0.1, 1.0);
      final baseX = cx + xPos * cx * perspScale * 1.4;
      final pillarH = amp * h * 0.25 * perspScale;

      final pillarColor = color.withValues(alpha: 0.4 + amp * 0.6);
      final pillarW = 3.0 * perspScale;

      canvas.drawLine(
        Offset(baseX, perspY),
        Offset(baseX, perspY - pillarH),
        Paint()
          ..color = pillarColor
          ..strokeWidth = pillarW
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }

    // Horizon glow line
    _drawGlowLine(
      canvas,
      Offset(0, horizon),
      Offset(w, horizon),
      color.withValues(alpha: 0.5 + bassEnergy * 0.5),
      1.5,
    );

    // Sun/circle at vanishing point
    final sunR = 30.0 + bassEnergy * 15.0;
    canvas.drawCircle(
      Offset(cx, horizon - sunR * 0.6),
      sunR,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, horizon - sunR * 0.6),
          sunR,
          [color.withValues(alpha: 0.4), color.withValues(alpha: 0.0)],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant NeonGridHorizonVisualizer old) => true;
}

// ═════════════════════════════════════════════════════════════════════════════
// 2. 3D SPECTRUM RING — FFT bars arranged in a rotating 3D circle
// ═════════════════════════════════════════════════════════════════════════════

class SpectrumRing3DVisualizer extends CustomPainter {
  final List<double> audioData;
  final Color color;
  final double time;

  static const int _barCount = 64;

  SpectrumRing3DVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(cx, cy) * 0.35;
    if (audioData.isEmpty) return;

    final rotY = time * math.pi * 2 * 0.4;
    final tiltX = math.pi * 0.25; // slight downward tilt

    // Collect bars with their z-depth for painter's algorithm
    final bars = <(double z, int i, double amp, Offset base, Offset top)>[];

    for (int i = 0; i < _barCount; i++) {
      final angle = (i / _barCount) * math.pi * 2;
      final amp = _band(audioData, i, _barCount);

      // Base point on ring
      var bx = math.cos(angle) * radius;
      var by = 0.0;
      var bz = math.sin(angle) * radius;

      // Bar extends outward radially
      final barLen = amp * radius * 0.8;
      var tx = math.cos(angle) * (radius + barLen);
      var ty = 0.0;
      var tz = math.sin(angle) * (radius + barLen);

      // Apply rotation
      (bx, by, bz) = _rotateY(bx, by, bz, rotY);
      (bx, by, bz) = _rotateX(bx, by, bz, tiltX);
      (tx, ty, tz) = _rotateY(tx, ty, tz, rotY);
      (tx, ty, tz) = _rotateX(tx, ty, tz, tiltX);

      final baseP = _project(bx, by, bz, cx, cy);
      final topP = _project(tx, ty, tz, cx, cy);

      bars.add((bz, i, amp, baseP, topP));
    }

    // Sort back-to-front
    bars.sort((a, b) => a.$1.compareTo(b.$1));

    for (final (z, _, amp, base, top) in bars) {
      final depthAlpha = (0.3 + _projectScale(z) * 0.7).clamp(0.2, 1.0);
      final barWidth = 1.5 + amp * 2.5;

      canvas.drawLine(
        base, top,
        Paint()
          ..color = color.withValues(alpha: (0.4 + amp * 0.6) * depthAlpha)
          ..strokeWidth = barWidth * _projectScale(z)
          ..strokeCap = StrokeCap.round
          ..maskFilter = amp > 0.3
              ? const MaskFilter.blur(BlurStyle.normal, 2) : null,
      );
    }

    // Ring outline
    final ringPath = Path();
    for (int i = 0; i <= _barCount; i++) {
      final angle = (i / _barCount) * math.pi * 2;
      var rx = math.cos(angle) * radius;
      var ry = 0.0;
      var rz = math.sin(angle) * radius;
      (rx, ry, rz) = _rotateY(rx, ry, rz, rotY);
      (rx, ry, rz) = _rotateX(rx, ry, rz, tiltX);
      final p = _project(rx, ry, rz, cx, cy);
      if (i == 0) ringPath.moveTo(p.dx, p.dy); else ringPath.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(ringPath, Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0);
  }

  @override
  bool shouldRepaint(covariant SpectrumRing3DVisualizer old) => true;
}

// ═════════════════════════════════════════════════════════════════════════════
// 3. RIBBON TRAIL — Luminous flowing ribbons through 3D space
// ═════════════════════════════════════════════════════════════════════════════

class RibbonTrailVisualizer extends CustomPainter {
  final List<double> audioData;
  final Color color;
  final double time;

  static const int _ribbons = 5;
  static const int _segments = 80;

  RibbonTrailVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = math.min(cx, cy) * 0.6;
    if (audioData.isEmpty) return;

    for (int r = 0; r < _ribbons; r++) {
      final ribbonPhase = r * math.pi * 2 / _ribbons;
      final path = Path();
      final alpha = (0.15 + (1.0 - (r / _ribbons - 0.5).abs() * 2) * 0.5).clamp(0.1, 0.65);

      for (int i = 0; i <= _segments; i++) {
        final t = i / _segments;
        final bandAmp = _smoothBand(audioData, i, _segments);

        // 3D spiral path
        final angle = t * math.pi * 4 + time * math.pi * 2 + ribbonPhase;
        final spread = maxR * (0.3 + bandAmp * 0.7);
        var x = math.cos(angle) * spread;
        var y = (t - 0.5) * size.height * 0.6 + math.sin(angle * 0.5 + time * 3) * bandAmp * 40;
        var z = math.sin(angle) * spread;

        // Slow rotation
        (x, y, z) = _rotateY(x, y, z, time * 0.5);

        final p = _project(x, y, z, cx, cy);
        if (i == 0) path.moveTo(p.dx, p.dy); else path.lineTo(p.dx, p.dy);
      }

      _drawGlowPath(canvas, path, color.withValues(alpha: alpha), 1.2 + r * 0.3);
    }
  }

  @override
  bool shouldRepaint(covariant RibbonTrailVisualizer old) => true;
}

// ═════════════════════════════════════════════════════════════════════════════
// 4. 3D LISSAJOUS — Parametric neon spirals in 3D space
// ═════════════════════════════════════════════════════════════════════════════

class Lissajous3DVisualizer extends CustomPainter {
  final List<double> audioData;
  final Color color;
  final double time;

  static const int _points = 400;
  static const int _trails = 3;

  Lissajous3DVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = math.min(cx, cy) * 0.55;
    if (audioData.isEmpty) return;

    // Audio-driven parameters
    double energy = 0;
    for (int i = 0; i < math.min(audioData.length, 32); i++) energy += audioData[i];
    energy = (energy / 32).clamp(0.0, 1.0);

    final freqA = 2.0 + energy * 2.0;
    final freqB = 3.0 + energy * 1.0;
    final freqC = 1.5 + energy * 1.5;
    final phase = time * math.pi * 2;

    for (int trail = 0; trail < _trails; trail++) {
      final trailOffset = trail * 0.08;
      final trailAlpha = (0.6 - trail * 0.15).clamp(0.1, 0.7);
      final path = Path();

      for (int i = 0; i <= _points; i++) {
        final t = i / _points * math.pi * 2;
        final dataIdx = (i * audioData.length / _points).floor().clamp(0, audioData.length - 1);
        final localAmp = audioData[dataIdx].clamp(0.0, 1.0);
        final r = maxR * (0.5 + localAmp * 0.5);

        var x = r * math.sin(freqA * t + phase - trailOffset);
        var y = r * math.cos(freqB * t + phase * 0.7 - trailOffset);
        var z = r * 0.5 * math.sin(freqC * t + phase * 0.4 - trailOffset);

        (x, y, z) = _rotateY(x, y, z, time * 0.3);

        final p = _project(x, y, z, cx, cy);
        if (i == 0) path.moveTo(p.dx, p.dy); else path.lineTo(p.dx, p.dy);
      }

      _drawGlowPath(canvas, path, color.withValues(alpha: trailAlpha), 1.5 - trail * 0.3);
    }
  }

  @override
  bool shouldRepaint(covariant Lissajous3DVisualizer old) => true;
}

// ═════════════════════════════════════════════════════════════════════════════
// 5. PARTICLE FIELD — Floating orbs with depth-of-field
// ═════════════════════════════════════════════════════════════════════════════

class ParticleFieldVisualizer extends CustomPainter {
  final List<double> audioData;
  final Color color;
  final double time;

  static const int _particleCount = 80;

  ParticleFieldVisualizer({
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

    // Overall energy
    double energy = 0;
    for (int i = 0; i < math.min(audioData.length, 32); i++) energy += audioData[i];
    energy = (energy / 32).clamp(0.0, 1.0);

    final rng = math.Random(42); // deterministic layout
    final particles = <(double z, double screenX, double screenY, double radius, double alpha)>[];

    for (int i = 0; i < _particleCount; i++) {
      // Deterministic base positions
      final baseX = (rng.nextDouble() - 0.5) * maxR * 2.5;
      final baseY = (rng.nextDouble() - 0.5) * maxR * 2.0;
      final baseZ = rng.nextDouble() * 400 + 50;

      // Audio modulation per particle
      final bandIdx = i % math.min(audioData.length, _particleCount).toInt();
      final amp = audioData[bandIdx].clamp(0.0, 1.0);

      // Gentle floating motion
      final px = baseX + math.sin(time * 0.8 + i * 0.3) * 20 * (1 + amp);
      final py = baseY + math.cos(time * 0.6 + i * 0.5) * 15 * (1 + amp);
      final pz = baseZ + math.sin(time * 0.4 + i * 0.7) * 30;

      final scale = _projectScale(pz);
      final screenX = px * scale + cx;
      final screenY = py * scale + cy;

      // Skip off-screen particles
      if (screenX < -20 || screenX > size.width + 20 ||
          screenY < -20 || screenY > size.height + 20) continue;

      final radius = (3.0 + amp * 8.0) * scale;
      final alpha = (0.15 + amp * 0.6) * scale;

      particles.add((pz, screenX, screenY, radius, alpha));
    }

    // Sort back to front
    particles.sort((a, b) => b.$1.compareTo(a.$1));

    final paint = Paint()..isAntiAlias = true;
    for (final (_, sx, sy, r, a) in particles) {
      // Outer glow
      paint
        ..color = color.withValues(alpha: (a * 0.3).clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 1.5);
      canvas.drawCircle(Offset(sx, sy), r * 2, paint);

      // Core
      paint
        ..color = color.withValues(alpha: a.clamp(0.0, 1.0))
        ..maskFilter = null;
      canvas.drawCircle(Offset(sx, sy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ParticleFieldVisualizer old) => true;
}

// ═════════════════════════════════════════════════════════════════════════════
// 6. WAVEFORM TUNNEL — Concentric waveform rings receding to vanishing point
// ═════════════════════════════════════════════════════════════════════════════

class WaveformTunnelVisualizer extends CustomPainter {
  final List<double> audioData; // signed waveform -1..1
  final Color color;
  final double time;

  static const int _ringCount = 20;
  static const int _pointsPerRing = 48;

  WaveformTunnelVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseR = math.min(cx, cy) * 0.5;
    if (audioData.isEmpty) return;

    final scrollZ = (time * 2.0) % 1.0;

    for (int ring = _ringCount - 1; ring >= 0; ring--) {
      final depth = (ring + scrollZ) / _ringCount;
      final z = depth * 500;
      final scale = _projectScale(z);
      final ringR = baseR * scale;
      final alpha = ((1.0 - depth) * 0.7).clamp(0.05, 0.7);

      if (ringR < 2) continue;

      final path = Path();
      for (int i = 0; i <= _pointsPerRing; i++) {
        final angle = (i / _pointsPerRing) * math.pi * 2;
        final dataIdx = (i * audioData.length / _pointsPerRing).floor().clamp(0, audioData.length - 1);
        final amp = audioData[dataIdx].clamp(-1.0, 1.0);

        // Waveform displaces the ring radius
        final displacement = amp * ringR * 0.3;
        final r = ringR + displacement;

        final px = cx + math.cos(angle) * r;
        final py = cy + math.sin(angle) * r;
        if (i == 0) path.moveTo(px, py); else path.lineTo(px, py);
      }
      path.close();

      canvas.drawPath(path, Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (1.5 * scale).clamp(0.3, 2.0)
        ..isAntiAlias = true);
    }
  }

  @override
  bool shouldRepaint(covariant WaveformTunnelVisualizer old) => true;
}

// ═════════════════════════════════════════════════════════════════════════════
// 7. KALEIDOSCOPE TUNNEL — Hexagonal tunnel with kaleidoscopic symmetry
// ═════════════════════════════════════════════════════════════════════════════

class KaleidoscopeTunnelVisualizer extends CustomPainter {
  final List<double> audioData;
  final Color color;
  final double time;

  static const int _symmetry = 6;
  static const int _layers = 12;

  KaleidoscopeTunnelVisualizer({
    required this.audioData,
    required this.color,
    this.time = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = math.min(cx, cy) * 0.8;
    if (audioData.isEmpty) return;

    double energy = 0;
    for (int i = 0; i < math.min(audioData.length, 16); i++) energy += audioData[i];
    energy = (energy / 16).clamp(0.0, 1.0);

    final rotation = time * math.pi * 0.3;
    final scrollZ = (time * 1.5) % 1.0;

    for (int layer = _layers - 1; layer >= 0; layer--) {
      final depth = (layer + scrollZ) / _layers;
      final z = depth * 400;
      final scale = _projectScale(z);
      final layerR = maxR * scale;

      if (layerR < 3) continue;

      final amp = _band(audioData, layer, _layers);
      final alpha = ((1.0 - depth) * 0.6 + amp * 0.2).clamp(0.05, 0.7);
      final layerRotation = rotation + layer * 0.15 + amp * 0.3;

      // Draw symmetric shape
      for (int s = 0; s < _symmetry; s++) {
        final segAngle = (s / _symmetry) * math.pi * 2 + layerRotation;
        final nextAngle = ((s + 1) / _symmetry) * math.pi * 2 + layerRotation;

        // Audio-modulated vertices
        final r1 = layerR * (0.7 + amp * 0.3);
        final r2 = layerR * (0.5 + energy * 0.5);

        final p1 = Offset(cx + math.cos(segAngle) * r1, cy + math.sin(segAngle) * r1);
        final p2 = Offset(cx + math.cos(nextAngle) * r1, cy + math.sin(nextAngle) * r1);
        final midAngle = (segAngle + nextAngle) / 2;
        final pMid = Offset(cx + math.cos(midAngle) * r2, cy + math.sin(midAngle) * r2);

        final path = Path()
          ..moveTo(p1.dx, p1.dy)
          ..quadraticBezierTo(pMid.dx, pMid.dy, p2.dx, p2.dy);

        canvas.drawPath(path, Paint()
          ..color = color.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (1.2 * scale).clamp(0.3, 2.0)
          ..isAntiAlias = true);
      }
    }
  }

  @override
  bool shouldRepaint(covariant KaleidoscopeTunnelVisualizer old) => true;
}
