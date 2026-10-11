/// How the radial scene answers a bass hit: a quick swell that springs back
/// past rest and settles, hits that arrive late landing as if on time, and a
/// shockwave for every hit worth one.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/visualizers/bass_beat.dart';
import 'package:eq_app/visualizers/radial_motion.dart';

BassHit hitOf(
  double strength, {
  double age = 0,
  double? gain,
  bool onset = true,
}) =>
    BassHit(age: age, strength: strength, gain: gain ?? strength, onset: onset);

/// Swell sampled every millisecond for [ms] milliseconds.
List<double> trace(RadialMotion m, int ms) => [
  for (var i = 0; i < ms; i++) (m..advance(0.001)).swell,
];

void main() {
  test('a full hit: up ~16% within ~40 ms, a rebound below rest, settled by 400 ms', () {
    final m = RadialMotion()..hit(hitOf(1));
    final t = trace(m, 400);
    final peak = t.reduce((a, b) => a > b ? a : b);
    final peakAt = t.indexOf(peak);
    expect(peak, closeTo(0.16, 0.01));
    expect(peakAt, inInclusiveRange(30, 50));
    expect(t.sublist(peakAt).reduce((a, b) => a < b ? a : b), lessThan(-0.01));
    expect(t.last.abs(), lessThan(0.005));
  });

  test('a softer hit is a smaller swell, and hits close together stack', () {
    final soft = trace(RadialMotion()..hit(hitOf(0.4)), 100);
    expect(soft.reduce((a, b) => a > b ? a : b), closeTo(0.064, 0.006));

    final m = RadialMotion()..hit(hitOf(1));
    trace(m, 30);
    m.hit(hitOf(1));
    final stacked = trace(m, 100).reduce((a, b) => a > b ? a : b);
    expect(stacked, greaterThan(0.2));
  });

  test('a hit reported late lands as if it had been seen on time', () {
    final onTime = RadialMotion()..hit(hitOf(1));
    onTime.advance(0.05);
    final late = RadialMotion();
    late.advance(0.03);
    late.hit(hitOf(1, age: 0.03));
    late.advance(0.02);
    expect(late.swell, closeTo(onTime.swell, 1e-9));
    expect(late.flare, closeTo(onTime.flare, 1e-9));
  });

  test('a ring for each hit worth one, launched once, gone when faded', () {
    final m = RadialMotion()..hit(hitOf(0.9));
    expect(m.rings, hasLength(1));
    // Topping the same hit up does not launch another.
    m.hit(hitOf(1, gain: 0.1, onset: false));
    expect(m.rings, hasLength(1));
    // A soft hit gets none...
    m.hit(hitOf(0.2));
    expect(m.rings, hasLength(1));
    // ...unless its attack tops it up past the threshold.
    m.hit(hitOf(0.6, gain: 0.4, onset: false));
    expect(m.rings, hasLength(2));
    final r0 = m.rings.first.r;
    m.advance(0.1);
    expect(m.rings.first.r, greaterThan(r0));
    m.advance(1.5);
    expect(m.rings, isEmpty);
  });

  test('the bass level breathes the core a little between hits', () {
    final m = RadialMotion()..level(1);
    m.advance(0.2);
    expect(m.breath, greaterThan(0.95));
    expect(m.swell, closeTo(0.035, 0.003));
    m.level(0);
    m.advance(0.05);
    expect(m.breath, inInclusiveRange(0.6, 0.8));
  });

  test('reset puts everything at rest', () {
    final m = RadialMotion()
      ..hit(hitOf(1))
      ..level(1)
      ..advance(0.02)
      ..reset();
    expect(m.swell, 0);
    expect(m.flare, 0);
    expect(m.rings, isEmpty);
  });
}
