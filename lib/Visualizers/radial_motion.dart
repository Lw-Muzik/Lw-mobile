/// The radial scene's bounce: what a bass hit does to the picture, and how it
/// settles.
///
/// # What a hit moves
///
/// - **The core swells** — the cover art jumps up to ~16% bigger on a full
///   hit and springs back, overshooting a little below rest, in ~250 ms. A
///   spring rather than a fixed curve so hits close together stack the way a
///   speaker cone does instead of restarting.
/// - **The crown flares** — every bar reaches further out, decaying with a
///   ~160 ms time constant ([flare]).
/// - **A shockwave leaves the core** on a hit of at least [_ringStrength].
///
/// Between hits the core still breathes with the bass level ([breath]), the
/// way a logo in the bass-driven visualizers of music channels does, so a
/// hit the detector judges too soft still moves the picture a little.
///
/// # Hits that arrive late
///
/// Hops come in batches (one per visualizer tick), so a hit is often a few
/// tens of milliseconds old when it is seen. Each hit carries its age, and
/// the spring is a linear system: its response to an impulse `age` seconds
/// ago is added exactly, rather than started now and drawn late.
library;

import 'dart:math' as math;

import 'bass_beat.dart';

/// One expanding shockwave. Radius and opacity are fractions: radius of the
/// smaller screen dimension, opacity of full.
class RadialRing {
  RadialRing(this.r, this.a, this.width);

  double r;
  double a;

  /// Stroke width, as a fraction of the smaller screen dimension.
  final double width;
}

/// Spring stiffness: ~5 Hz, so the swell peaks ~40 ms after the hit.
const double _omega = 2 * math.pi * 5.0;

/// Below 1 so it overshoots: a bounce, not a fade.
const double _damping = 0.5;

/// Initial velocity per unit of hit, set so a full hit peaks near 0.16.
const double _impulse = 0.293 * _omega;

const double _flareTau = 0.16;
const double _ringStrength = 0.4;

/// Core edge at rest, as a fraction of the smaller screen dimension.
const double kRadialCore = 0.2;

class RadialMotion {
  double _x = 0;
  double _v = 0;
  double _flare = 0;
  double _breath = 0;
  bool _ringOwed = false;

  /// Live shockwaves, oldest first.
  final List<RadialRing> rings = [];

  /// How much bigger than rest the core is drawn: 0 at rest, ~0.16 at the
  /// top of a full hit, slightly negative on the rebound.
  double get swell => (_x + _breath * 0.035).clamp(-0.06, 0.32);

  /// The crown's flare, 0..1.
  double get flare => _flare;

  /// The bass level, smoothed, 0..1.
  double get breath => _breath;

  /// Answers one report from [BassBeat].
  void hit(BassHit hit) {
    final a = math.max(0.0, hit.age);
    final v0 = hit.gain * _impulse;
    final wd = _omega * math.sqrt(1 - _damping * _damping);
    final decay = math.exp(-_damping * _omega * a);
    final s = math.sin(wd * a);
    final c = math.cos(wd * a);
    _x += v0 * decay * s / wd;
    _v += v0 * decay * (c - _damping * _omega / wd * s);

    _flare = math.max(_flare, hit.strength * math.exp(-a / _flareTau));

    if (hit.onset) _ringOwed = true;
    if (_ringOwed && hit.strength >= _ringStrength) {
      _ringOwed = false;
      final ring = RadialRing(
        kRadialCore,
        0.22 + 0.4 * hit.strength,
        0.003 + 0.004 * hit.strength,
      );
      _advanceRing(ring, a);
      if (ring.a > 0) rings.add(ring);
    }
  }

  /// Follows the bass level between hits.
  void level(double bass) {
    _breath = bass;
  }

  /// Moves everything on by [dt] seconds.
  void advance(double dt) {
    if (dt <= 0) return;
    final wd = _omega * math.sqrt(1 - _damping * _damping);
    final decay = math.exp(-_damping * _omega * dt);
    final c = math.cos(wd * dt);
    final s = math.sin(wd * dt);
    final x = _x;
    final v = _v;
    _x = decay * (x * c + (v + _damping * _omega * x) / wd * s);
    _v = decay * (v * c - (_omega * _omega * x + _damping * _omega * v) / wd * s);
    _flare *= math.exp(-dt / _flareTau);
    for (var k = rings.length - 1; k >= 0; k--) {
      _advanceRing(rings[k], dt);
      if (rings[k].a <= 0) rings.removeAt(k);
    }
  }

  void _advanceRing(RadialRing ring, double dt) {
    ring.r += dt * 0.85;
    ring.a -= dt * 0.75;
  }

  /// Back to rest: a track change or a seek should not carry a bounce over.
  void reset() {
    _x = 0;
    _v = 0;
    _flare = 0;
    _breath = 0;
    _ringOwed = false;
    rings.clear();
  }
}
