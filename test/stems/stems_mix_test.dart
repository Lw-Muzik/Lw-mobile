/// The Stems tab's rules: what a pad, a fader and a combo each do to the mix
/// the native engine is given, and when the mix counts as "changed".
///
/// Every one of these is invisible when wrong in a way that looks like a
/// broken song rather than a bug: a combo that moves faders loses the user's
/// mix, an `engaged` that is off by a hair leaves the engine running (and the
/// "Stems on" dot lit) on a mix that is the original.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/models/stems_mix.dart';

void main() {
  group('initial mix', () {
    const mix = StemsMix.initial;

    test('is the original: every fader at 100%, every pad on', () {
      expect(mix.faders, [1.0, 1.0, 1.0]);
      expect(mix.pads, [true, true, true]);
      expect(mix.effectiveLevels, [1.0, 1.0, 1.0]);
    });

    test('is not engaged, has no lit combo, and has nothing to reset', () {
      expect(mix.engaged, isFalse);
      expect(mix.activeCombo, isNull);
      expect(mix.isDefault, isTrue);
    });
  });

  group('pads', () {
    test('off mutes the stem but remembers its fader', () {
      final mix = StemsMix.initial
          .withFader(Stem.vocals, 0.6)
          .togglePad(Stem.vocals);
      expect(mix.padOn(Stem.vocals), isFalse);
      expect(mix.fader(Stem.vocals), 0.6);
      expect(mix.effective(Stem.vocals), 0.0);
      expect(mix.effectiveLevels, [0.0, 1.0, 1.0]);
    });

    test('back on restores the remembered level', () {
      final mix = StemsMix.initial
          .withFader(Stem.drums, 0.35)
          .togglePad(Stem.drums)
          .togglePad(Stem.drums);
      expect(mix.effective(Stem.drums), 0.35);
    });

    test('off on a stem at 100% engages the mix', () {
      final mix = StemsMix.initial.togglePad(Stem.instruments);
      expect(mix.engaged, isTrue);
    });
  });

  group('faders', () {
    test('a level below 100% engages the mix', () {
      final mix = StemsMix.initial.withFader(Stem.drums, 0.5);
      expect(mix.effectiveLevels, [1.0, 0.5, 1.0]);
      expect(mix.engaged, isTrue);
    });

    test('moving the fader of a muted stem switches its pad back on', () {
      final mix = StemsMix.initial
          .tapCombo(StemCombo.karaoke)
          .withFader(Stem.vocals, 0.3);
      expect(mix.padOn(Stem.vocals), isTrue);
      expect(mix.effective(Stem.vocals), 0.3);
      expect(mix.activeCombo, isNull, reason: 'vocals are audible again');
    });

    test('are clamped to 0–1', () {
      final mix = StemsMix(
        faders: const [1.4, -0.2, 0.5],
        pads: const [true, true, true],
      );
      expect(mix.faders, [1.0, 0.0, 0.5]);
    });
  });

  group('engaged', () {
    test('ignores differences smaller than the epsilon', () {
      final nearlyUnity = StemsMix(
        faders: const [0.9995, 1.0, 1.0],
        pads: const [true, true, true],
      );
      expect(nearlyUnity.engaged, isFalse);
    });

    test('catches the smallest step a fader can make below 100%', () {
      // 99% is inside the sticky zone at the top, so 98% is the first stop.
      expect(quantizeFader(0.99), 1.0);
      final mix = StemsMix.initial.withFader(Stem.vocals, quantizeFader(0.98));
      expect(mix.fader(Stem.vocals), 0.98);
      expect(mix.engaged, isTrue);
    });

    test('a fader back at 100% disengages', () {
      final mix = StemsMix.initial
          .withFader(Stem.vocals, 0.4)
          .withFader(Stem.vocals, 1.0);
      expect(mix.engaged, isFalse);
      expect(mix.isDefault, isTrue);
    });
  });

  group('combos', () {
    test('each sets exactly its pad pattern', () {
      expect(StemsMix.initial.tapCombo(StemCombo.acapella).pads, [
        true,
        false,
        false,
      ]);
      expect(StemsMix.initial.tapCombo(StemCombo.karaoke).pads, [
        false,
        true,
        true,
      ]);
      expect(StemsMix.initial.tapCombo(StemCombo.drumsOnly).pads, [
        false,
        true,
        false,
      ]);
    });

    test('is lit when the pads match it, however they got there', () {
      final byHand = StemsMix.initial
          .togglePad(Stem.drums)
          .togglePad(Stem.instruments);
      expect(byHand.activeCombo, StemCombo.acapella);
    });

    test('tapping a lit combo turns every pad back on', () {
      final mix = StemsMix.initial
          .tapCombo(StemCombo.karaoke)
          .tapCombo(StemCombo.karaoke);
      expect(mix.pads, [true, true, true]);
      expect(mix.activeCombo, isNull);
    });

    test('tapping another combo switches straight to its pattern', () {
      final mix = StemsMix.initial
          .tapCombo(StemCombo.karaoke)
          .tapCombo(StemCombo.drumsOnly);
      expect(mix.activeCombo, StemCombo.drumsOnly);
    });

    test('never touch the faders', () {
      final before = StemsMix.initial
          .withFader(Stem.vocals, 0.7)
          .withFader(Stem.drums, 0.2)
          .withFader(Stem.instruments, 0.9);
      for (final combo in StemCombo.values) {
        final lit = before.tapCombo(combo);
        expect(lit.faders, before.faders, reason: '${combo.name} on');
        expect(
          lit.tapCombo(combo).faders,
          before.faders,
          reason: '${combo.name} off',
        );
      }
    });

    test('effective levels follow the pattern over the remembered faders', () {
      final mix = StemsMix.initial
          .withFader(Stem.drums, 0.5)
          .tapCombo(StemCombo.drumsOnly);
      expect(mix.effectiveLevels, [0.0, 0.5, 0.0]);
    });
  });

  test('reset restores every fader to 100% and every pad on', () {
    final mix = StemsMix.initial
        .withFader(Stem.vocals, 0.1)
        .withFader(Stem.drums, 0.0)
        .tapCombo(StemCombo.acapella)
        .reset();
    expect(mix, StemsMix.initial);
    expect(mix.engaged, isFalse);
  });

  group('quantizeFader', () {
    test('rounds to whole percent', () {
      expect(quantizeFader(0.4249), 0.42);
      expect(quantizeFader(0.4251), 0.43);
    });

    test('makes both ends sticky', () {
      expect(quantizeFader(0.99), 1.0);
      expect(quantizeFader(0.986), 1.0);
      expect(quantizeFader(0.014), 0.0);
      expect(quantizeFader(0.97), 0.97);
      expect(quantizeFader(0.03), 0.03);
    });

    test('clamps and survives NaN', () {
      expect(quantizeFader(1.7), 1.0);
      expect(quantizeFader(-3), 0.0);
      expect(quantizeFader(double.nan), 1.0);
    });
  });

  group('stemsArmed', () {
    test('while the tab is visible, or while the mix is engaged', () {
      expect(stemsArmed(tabVisible: false, engaged: false), isFalse);
      expect(stemsArmed(tabVisible: true, engaged: false), isTrue);
      expect(stemsArmed(tabVisible: false, engaged: true), isTrue);
      expect(stemsArmed(tabVisible: true, engaged: true), isTrue);
    });
  });
}
