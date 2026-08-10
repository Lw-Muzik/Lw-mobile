/// Collapsing the background's two stacked blurs into one.
///
/// The app shell used to paint two full-screen `BackdropFilter`s on top of each
/// other — the user's blur, then a fixed 200 — and both were recomputed every
/// frame the app produced. They are now one `ImageFiltered` pass over the
/// artwork. That is only a free change if the single sigma really is equivalent
/// to the pair, which is the one claim here worth pinning down: get it wrong and
/// nobody sees a crash, the background just quietly stops looking the same.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/widgets/Body.dart';

void main() {
  group('backgroundBlurSigma', () {
    test('is the user blur alone when nothing washes the cover out', () {
      expect(backgroundBlurSigma(40, washed: false), 40);
      expect(backgroundBlurSigma(0, washed: false), 0);
    });

    test('composes the two Gaussians rather than adding them', () {
      // sqrt(40^2 + 200^2) — NOT 240, and not 200.
      expect(
        backgroundBlurSigma(40, washed: true),
        closeTo(203.96, 0.01),
      );
      expect(backgroundBlurSigma(40, washed: true), lessThan(240));
      expect(backgroundBlurSigma(40, washed: true), greaterThan(kWashSigma));
    });

    test('degenerates to the wash alone when the user blur is zero', () {
      expect(backgroundBlurSigma(0, washed: true), kWashSigma);
    });

    test('matches the stacked-pair identity across the settings range', () {
      // The blur slider's span. Each value must satisfy the same identity the
      // two stacked filters produced: s = sqrt(s1^2 + s2^2).
      for (final blur in <double>[0, 5, 10, 25, 40, 60, 80, 100]) {
        expect(
          backgroundBlurSigma(blur, washed: true),
          closeTo(math.sqrt(blur * blur + kWashSigma * kWashSigma), 1e-9),
          reason: 'blur=$blur',
        );
      }
    });

    test('never returns less than either blur it replaces', () {
      for (final blur in <double>[0, 40, 100, 300]) {
        final combined = backgroundBlurSigma(blur, washed: true);
        expect(combined, greaterThanOrEqualTo(blur));
        expect(combined, greaterThanOrEqualTo(kWashSigma));
      }
    });
  });
}
