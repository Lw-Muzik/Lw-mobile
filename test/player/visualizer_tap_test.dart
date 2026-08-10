/// Deciding when the native FFT/PCM tap runs.
///
/// Extracted from `AppController` and tested on its own because the rule is no
/// longer "whatever the master switch says". The master switch is gone; the tap
/// is now implied by the two surfaces that actually draw it, and getting the
/// implication wrong is invisible on screen — a tap left running costs CPU on
/// every audio buffer with nothing to show for it, and a tap wrongly stopped
/// leaves a visualizer frozen with no error anywhere.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/controllers/visualizer_tap.dart';

void main() {
  group('shouldRun', () {
    test('is false when no surface draws the visualizer', () {
      final tap = VisualizerTap();
      expect(tap.shouldRun, isFalse);
    });

    test('is true when only the player visual is on', () {
      final tap = VisualizerTap()..playerVisual = true;
      expect(tap.shouldRun, isTrue);
    });

    test('is true when only the background visual is on', () {
      final tap = VisualizerTap()..backgroundVisual = true;
      expect(tap.shouldRun, isTrue);
    });

    test('stays true while either surface still wants it', () {
      final tap = VisualizerTap()
        ..playerVisual = true
        ..backgroundVisual = true;

      tap.playerVisual = false;
      expect(tap.shouldRun, isTrue,
          reason: 'the background visual is still drawing it');

      tap.backgroundVisual = false;
      expect(tap.shouldRun, isFalse);
    });
  });

  group('pendingPush', () {
    test('reports the first state so the native side is initialised', () {
      final tap = VisualizerTap();
      expect(tap.pendingPush(), isFalse,
          reason: 'native starts in an unknown state and must be told');
      expect(tap.pendingPush(), isNull, reason: 'already pushed');
    });

    test('reports nothing when the desired state has not changed', () {
      final tap = VisualizerTap();
      tap.pendingPush();

      tap.playerVisual = true;
      expect(tap.pendingPush(), isTrue);
      expect(tap.pendingPush(), isNull);
      expect(tap.pendingPush(), isNull);
    });

    test('does not push when a toggle flips but the OR does not', () {
      final tap = VisualizerTap()
        ..playerVisual = true
        ..backgroundVisual = true;
      tap.pendingPush();

      // One surface goes away, the other still needs the tap: nothing to say
      // to the native side.
      tap.playerVisual = false;
      expect(tap.pendingPush(), isNull);
    });

    test('pushes again after the state returns to a previous value', () {
      final tap = VisualizerTap();
      tap.pendingPush();

      tap.playerVisual = true;
      expect(tap.pendingPush(), isTrue);

      tap.playerVisual = false;
      expect(tap.pendingPush(), isFalse);
    });
  });

  group('suspend / resume', () {
    test('suspend stops the tap without forgetting what the user wanted', () {
      final tap = VisualizerTap()..playerVisual = true;
      tap.pendingPush();

      tap.suspended = true;
      expect(tap.shouldRun, isFalse);
      expect(tap.pendingPush(), isFalse);

      tap.suspended = false;
      expect(tap.shouldRun, isTrue);
      expect(tap.pendingPush(), isTrue);
    });

    test('resuming with every surface off leaves the tap off', () {
      final tap = VisualizerTap();
      tap.pendingPush();

      tap.suspended = true;
      expect(tap.pendingPush(), isNull, reason: 'it was already off');

      tap.suspended = false;
      expect(tap.pendingPush(), isNull);
    });
  });
}
