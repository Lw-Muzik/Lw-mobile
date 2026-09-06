/// Energy-onset beat detection.
///
/// A direct port of the desktop app's `src/lib/beat.ts`, constant for constant,
/// so a scene tuned against one behaves identically on the other. The desktop
/// comment is worth keeping because it explains the choice: track a slow
/// running average of the channel level and fire a pulse whenever the
/// instantaneous level jumps well above it (an onset — kicks, snares, plucks).
/// The pulse then decays smoothly, so the UI reads as pulsing on the beat
/// without needing real tempo analysis.
///
/// # Why the numbers must not drift
///
/// Every visual that reacts to [pulse] was tuned against these four constants.
/// Changing one here and not on desktop is how the "same" visualizer ends up
/// feeling different on the two platforms, which is exactly what this port
/// exists to prevent.
library;

import 'dart:math' as math;

/// Instantaneous level must exceed `avg * onsetRatio` to count as an onset.
const double _onsetRatio = 1.45;

/// Ignore onsets below this absolute level (near-silence / noise floor).
const double _onsetFloor = 0.06;

/// Pulse decay time constant in seconds (smaller = snappier).
const double _pulseTau = 0.13;

/// Running-average smoothing per ~60fps frame.
const double _avgAlpha = 0.12;

/// One channel's detector state.
///
/// Mutable and stepped in place, unlike the desktop version which returns a new
/// object each frame: this runs inside a Flutter painter's host, where a fresh
/// allocation every frame for every channel is exactly the kind of garbage that
/// shows up as jank on a mid-range phone.
class BeatState {
  /// Slow running average level — the adaptive onset threshold baseline.
  double avg = 0;

  /// Current pulse envelope (0..1): spikes on an onset, then decays.
  double pulse = 0;

  BeatState();

  /// Advance this channel's envelope by a single frame.
  ///
  /// [level] is the channel level 0..1, [dt] the seconds since the previous
  /// frame — which is what keeps the decay rate independent of frame rate, so a
  /// phone dropping to 30fps pulses at the same speed as one holding 60.
  void step(double level, double dt) {
    final v = level.isFinite ? math.max(0.0, level) : 0.0;
    final onset = v > _onsetFloor && v > avg * _onsetRatio;
    final decayed = pulse * math.exp(-math.max(0.0, dt) / _pulseTau);
    // An onset snaps the pulse up to the onset strength; otherwise it decays.
    pulse = onset ? math.min(1.0, math.max(decayed, v)) : decayed;
    avg += (v - avg) * _avgAlpha;
  }

  void reset() {
    avg = 0;
    pulse = 0;
  }
}
