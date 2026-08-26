/// The player card deck's arithmetic.
///
/// The bug being designed out here is "the card snaps at the end of a swipe".
/// It was never a tuning problem: the throw, the stack rise and the snap-back
/// ran on three independent 380/350/250 ms timelines, so the stack finished
/// moving at a different instant than the index committed, and the difference
/// showed as a jump. The continuity group below is the guarantee that replaced
/// them — if it passes, there is no instant at which the deck can jump.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/player/deck_motion.dart';

void main() {
  group('reconcile — the deck follows whatever moved the index', () {
    test('already showing the track', () {
      expect(reconcile(shown: 3, target: 3), DeckStep.none);
    });

    test('one forward is a throw, whatever caused it', () {
      // A swipe, the track ending, a crossfade starting, a headphone button,
      // the notification — all of them arrive here as the same +1.
      expect(reconcile(shown: 0, target: 1), DeckStep.next);
      expect(reconcile(shown: 41, target: 42), DeckStep.next);
    });

    test('one back brings the previous card home', () {
      expect(reconcile(shown: 5, target: 4), DeckStep.previous);
    });

    // A cross-fade of two album covers does not read as distance; it reads as
    // a flicker. Distance now decides where the deck lands, never how it moves.
    test('a jump of more than one is still a card move, in the right direction',
        () {
      expect(reconcile(shown: 0, target: 40), DeckStep.next);
      expect(reconcile(shown: 40, target: 0), DeckStep.previous);
      expect(reconcile(shown: 5, target: 7), DeckStep.next);
      expect(reconcile(shown: 5, target: 3), DeckStep.previous);
    });

    test('a repeat-all wrap is one card, not a jump across the queue', () {
      // next() on the last track under repeat-all sets the index to 0. By
      // arithmetic that is 40 tracks backward; to the user it is one forward.
      expect(
        reconcile(shown: 40, target: 0, itemCount: 41),
        DeckStep.next,
      );
      expect(
        reconcile(shown: 0, target: 40, itemCount: 41),
        DeckStep.previous,
      );
    });

    test('without a queue length a wrap reads as a long move backwards', () {
      expect(reconcile(shown: 40, target: 0), DeckStep.previous);
    });

    test('a real jump to the ends moves in the direction of travel', () {
      // Tapping the last track in a 60-item queue from track 5.
      expect(reconcile(shown: 5, target: 59, itemCount: 60), DeckStep.next);
      expect(reconcile(shown: 5, target: 0, itemCount: 60), DeckStep.previous);
    });

    test('a two-track queue reads the move by its delta', () {
      // Both readings describe the same movement, so the simple one wins
      // rather than inventing a wrap.
      expect(reconcile(shown: 1, target: 0, itemCount: 2), DeckStep.previous);
      expect(reconcile(shown: 0, target: 1, itemCount: 2), DeckStep.next);
    });
  });

  group('resolveDrag', () {
    const width = 400.0;

    test('a short slow drag goes back where it came from', () {
      expect(
        resolveDrag(
          dx: 20,
          velocity: 50,
          width: width,
          canNext: true,
          canPrevious: true,
        ),
        DragOutcome.snapBack,
      );
    });

    test('distance alone commits', () {
      expect(
        resolveDrag(
          dx: width * 0.4,
          velocity: 0,
          width: width,
          canNext: true,
          canPrevious: true,
        ),
        DragOutcome.next,
      );
    });

    test('speed alone commits, even from barely anywhere', () {
      expect(
        resolveDrag(
          dx: 5,
          velocity: 2500,
          width: width,
          canNext: true,
          canPrevious: true,
        ),
        DragOutcome.next,
      );
    });

    test('a flick back is read by its velocity, not where the finger ended', () {
      // Dragged right, then flicked left and released past centre: the throw is
      // leftward. Reading dx here would send the deck the wrong way.
      expect(
        resolveDrag(
          dx: 30,
          velocity: -2000,
          width: width,
          canNext: true,
          canPrevious: true,
        ),
        DragOutcome.previous,
      );
    });

    test('backward drag goes back', () {
      expect(
        resolveDrag(
          dx: -width * 0.4,
          velocity: 0,
          width: width,
          canNext: true,
          canPrevious: true,
        ),
        DragOutcome.previous,
      );
    });

    test('an edge of the queue snaps back instead of committing', () {
      expect(
        resolveDrag(
          dx: width * 0.9,
          velocity: 4000,
          width: width,
          canNext: false,
          canPrevious: true,
        ),
        DragOutcome.snapBack,
      );
      expect(
        resolveDrag(
          dx: -width * 0.9,
          velocity: -4000,
          width: width,
          canNext: true,
          canPrevious: false,
        ),
        DragOutcome.snapBack,
      );
    });
  });

  group('layoutAt', () {
    test('the front card is untouched', () {
      final front = layoutAt(0);
      expect(front.scale, 1.0);
      expect(front.dy, 0.0);
      expect(front.opacity, 1.0);
    });

    test('deeper cards are smaller, higher and fainter', () {
      final one = layoutAt(1);
      final two = layoutAt(2);
      expect(two.scale, lessThan(one.scale));
      expect(two.dy, lessThan(one.dy)); // further up the screen
      expect(two.opacity, lessThan(one.opacity));
    });

    test('opacity cannot go negative on a deep stack', () {
      expect(layoutAt(50).opacity, 0.0);
    });
  });

  group('continuity — the property that removes the snap', () {
    // At the instant a forward step finishes, every card is drawn at depth
    // d - 1. The index then commits and that same card is genuinely at depth
    // d - 1. If those two renderings differ by even a fraction, that difference
    // is the visible jump.
    test('a completed forward step already looks like the committed deck', () {
      for (var depth = 0; depth <= 4; depth++) {
        final duringStep =
            layoutAt(depth + stackShift(DeckStep.next, 1.0));
        final afterCommit = layoutAt(depth - 1.0);

        expect(duringStep.scale, afterCommit.scale, reason: 'depth $depth');
        expect(duringStep.dy, afterCommit.dy, reason: 'depth $depth');
        expect(duringStep.opacity, afterCommit.opacity, reason: 'depth $depth');
      }
    });

    test('a completed backward step already looks like the committed deck', () {
      for (var depth = 0; depth <= 4; depth++) {
        final duringStep =
            layoutAt(depth + stackShift(DeckStep.previous, 1.0));
        final afterCommit = layoutAt(depth + 1.0);

        expect(duringStep.scale, afterCommit.scale, reason: 'depth $depth');
        expect(duringStep.dy, afterCommit.dy, reason: 'depth $depth');
        expect(duringStep.opacity, afterCommit.opacity, reason: 'depth $depth');
      }
    });

    test('the incoming previous card lands exactly on the front slot', () {
      // It rests at -1, so a completed backward step puts it at 0 — the front
      // card's geometry, to the pixel.
      final arriving = layoutAt(-1 + stackShift(DeckStep.previous, 1.0));
      final front = layoutAt(0);
      expect(arriving.scale, front.scale);
      expect(arriving.dy, front.dy);
      expect(arriving.opacity, front.opacity);
    });

    test('geometry never jumps anywhere in the middle of a step', () {
      // Walk a step in small increments; no sample may differ from the last by
      // more than the whole step's travel. A discontinuity anywhere shows here.
      const steps = 200;
      var previous = layoutAt(1 + stackShift(DeckStep.next, 0));
      for (var i = 1; i <= steps; i++) {
        final layout = layoutAt(1 + stackShift(DeckStep.next, i / steps));
        expect((layout.scale - previous.scale).abs(), lessThan(0.01));
        expect((layout.dy - previous.dy).abs(), lessThan(1.0));
        expect((layout.opacity - previous.opacity).abs(), lessThan(0.01));
        previous = layout;
      }
    });

    test('a step that is not running moves nothing', () {
      expect(stackShift(DeckStep.none, 0.7), 0.0);
      expect(stackShift(DeckStep.none, 0.7), 0.0);
    });
  });
}
