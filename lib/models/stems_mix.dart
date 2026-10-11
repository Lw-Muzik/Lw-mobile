/// The rules behind the Stems tab: three faders, three pads, three combos.
///
/// Spleeter splits a song four ways — vocals, drums, bass and "other" — but to
/// anyone who isn't producing the track, bass and "other" are both just the
/// instruments, so they share one control. The native engine mixes
/// `out = gV·V + gD·D + gI·(x − V − D)`, which is the original sample for
/// sample while all three gains are 1. That is why 100% is the top of every
/// fader and why "nothing changed" is a state worth detecting exactly.
///
/// Everything here is pure so it can be tested without a widget, a channel or
/// a clock.
library;

import 'package:flutter/foundation.dart';

/// One control on the Stems tab, in the order the native levels map uses.
enum Stem {
  vocals('Vocals'),
  drums('Drums'),
  instruments('Instruments');

  const Stem(this.label);

  final String label;
}

/// A one-tap pad pattern.
///
/// A combo is *only* a set of pad states. Faders keep their values, so leaving
/// a combo puts the mix back exactly where it was.
enum StemCombo {
  acapella('Acapella', [true, false, false]),
  karaoke('Karaoke', [false, true, true]),
  drumsOnly('Drums only', [false, true, false]);

  const StemCombo(this.label, this.pads);

  final String label;

  /// Pad states in [Stem] order.
  final List<bool> pads;
}

/// Faders move in whole percent so the readout never flickers between two
/// values on a still finger, and the two ends are sticky: 100% is "the
/// original" and 0% is "gone", the two positions people actually aim for, and
/// the two hardest to land on by dragging.
double quantizeFader(double raw) {
  if (raw.isNaN) return 1.0;
  final v = raw.clamp(0.0, 1.0);
  if (v >= 0.985) return 1.0;
  if (v <= 0.015) return 0.0;
  return (v * 100).roundToDouble() / 100;
}

/// Whether the native engine should be working.
///
/// It runs while the Stems tab is on screen — so a song is already being
/// prepared by the time someone reaches for a fader — and for as long as the
/// mix is audibly different from the original, wherever the user has gone.
bool stemsArmed({required bool tabVisible, required bool engaged}) =>
    tabVisible || engaged;

@immutable
class StemsMix {
  /// The level a stem has in the original recording.
  static const double unity = 1.0;

  /// How far below [unity] an effective level has to be to count as changed.
  /// Faders move in 1% steps, so anything a person can set is well clear of it.
  static const double engagedEpsilon = 1e-3;

  /// Fader positions, 0–1, in [Stem] order. Remembered while a pad is off.
  final List<double> faders;

  /// Pad states in [Stem] order. Off mutes the stem without moving its fader.
  final List<bool> pads;

  const StemsMix._(this.faders, this.pads);

  /// Everything at the original level: what every app start begins with.
  static const StemsMix initial = StemsMix._(
    [1.0, 1.0, 1.0],
    [true, true, true],
  );

  factory StemsMix({required List<double> faders, required List<bool> pads}) {
    assert(faders.length == Stem.values.length);
    assert(pads.length == Stem.values.length);
    return StemsMix._(
      List.unmodifiable([for (final f in faders) f.clamp(0.0, 1.0)]),
      List.unmodifiable(pads),
    );
  }

  double fader(Stem stem) => faders[stem.index];

  bool padOn(Stem stem) => pads[stem.index];

  /// What the stem is actually played at: its fader, or silence while its pad
  /// is off.
  double effective(Stem stem) => pads[stem.index] ? faders[stem.index] : 0.0;

  /// The gains the native engine is given, in [Stem] order.
  List<double> get effectiveLevels => [
    for (final stem in Stem.values) effective(stem),
  ];

  /// Whether the mix differs audibly from the original.
  bool get engaged =>
      effectiveLevels.any((level) => level < unity - engagedEpsilon);

  /// Whether there is anything for Reset to undo.
  bool get isDefault => this == initial;

  /// The combo whose pattern the pads currently match, if any.
  StemCombo? get activeCombo {
    for (final combo in StemCombo.values) {
      if (listEquals(combo.pads, pads)) return combo;
    }
    return null;
  }

  /// Moves a fader. A stem whose pad is off is switched back on by it.
  ///
  /// Someone dragging the vocals fader up after choosing Karaoke wants to hear
  /// the vocals come back; a fader that moves while the sound stays silent
  /// reads as broken, not as "muted".
  StemsMix withFader(Stem stem, double value) {
    final faders = [...this.faders]..[stem.index] = value.clamp(0.0, 1.0);
    final pads = [...this.pads]..[stem.index] = true;
    return StemsMix(faders: faders, pads: pads);
  }

  StemsMix withPad(Stem stem, bool on) {
    final pads = [...this.pads]..[stem.index] = on;
    return StemsMix(faders: faders, pads: pads);
  }

  StemsMix togglePad(Stem stem) => withPad(stem, !padOn(stem));

  /// Tapping a lit combo turns every pad back on; tapping any other sets the
  /// pads to its pattern. Faders are never touched.
  StemsMix tapCombo(StemCombo combo) {
    if (activeCombo == combo) {
      return StemsMix(faders: faders, pads: const [true, true, true]);
    }
    return StemsMix(faders: faders, pads: combo.pads);
  }

  /// Every fader to 100% and every pad on.
  StemsMix reset() => initial;

  @override
  bool operator ==(Object other) =>
      other is StemsMix &&
      listEquals(other.faders, faders) &&
      listEquals(other.pads, pads);

  @override
  int get hashCode => Object.hash(Object.hashAll(faders), Object.hashAll(pads));

  @override
  String toString() => 'StemsMix(faders: $faders, pads: $pads)';
}
