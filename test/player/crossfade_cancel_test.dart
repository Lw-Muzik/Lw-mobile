/// Cancelling a crossfade that has not started fading yet.
///
/// A crossfade is two phases, and only the second one used to be interruptible:
///
/// 1. **Setup** — load the next track on the spare player (a network fetch for
///    a streamed track), read its replay gain, fetch its artwork. Unbounded.
/// 2. **The fade** — twenty volume steps over the configured duration.
///
/// `abortCrossfade` waits for the whole thing, and the cancel flag was only
/// read inside the loop. So tapping next while the setup was still running did
/// nothing at all until the network came back — the track kept playing, the new
/// one did not start, and the button looked broken. That is the bug this file
/// is about.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/player/fade_cancellation.dart';

void main() {
  group('a fade wakes the moment it is cancelled', () {
    test('a pending step returns immediately on cancel', () async {
      final cancellation = FadeCancellation();
      final watch = Stopwatch()..start();

      final step = cancellation.wait(const Duration(seconds: 10));
      cancellation.cancel();
      await step;

      expect(watch.elapsed, lessThan(const Duration(seconds: 1)),
          reason: 'the step must not run to term — at a 20 s crossfade that is '
              'a whole second of a dead next button');
      expect(cancellation.isCancelled, isTrue);
    });

    test('an uncancelled step waits out its duration', () async {
      final cancellation = FadeCancellation();
      final watch = Stopwatch()..start();

      await cancellation.wait(const Duration(milliseconds: 120));

      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(100));
      expect(cancellation.isCancelled, isFalse);
    });

    test('cancelling before the wait skips it entirely', () async {
      final cancellation = FadeCancellation()..cancel();
      final watch = Stopwatch()..start();

      await cancellation.wait(const Duration(seconds: 10));

      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    /// The setup does several awaits in a row. Each one asks again, so a cancel
    /// arriving during any of them is acted on at the next opportunity rather
    /// than at the end of all of them.
    test('cancelling twice is harmless', () {
      final cancellation = FadeCancellation()
        ..cancel()
        ..cancel();
      expect(cancellation.isCancelled, isTrue);
    });
  });
}
