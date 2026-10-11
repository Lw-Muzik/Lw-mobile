/// Bass-hit detection: a kick, an 808, a log drum — whatever lands in the low
/// end with an attack.
///
/// # Why not [BeatState]
///
/// `BeatState` (beat_detector.dart) watches the whole mix's level and fires
/// when it jumps 1.45x over its running average. A mastered song barely moves
/// its full-band level between kicks — the hats, pads and vocals hold it up —
/// so most kicks never cleared the ratio. Replayed through the app's own
/// pipeline, three real songs had 21-53% of their bass hits answered, plus
/// off-beat pulses on snares and vocal stabs.
///
/// This listens to the band below ~150 Hz only, where a kick is most of the
/// energy, and in decibels, where "a hit" is a rise of a few dB whatever the
/// song's loudness. Against the same three songs it answers 95-100% of the
/// big bass attacks.
///
/// # How a hit is told from everything else
///
/// - **It rises sharply** — at least [_fastRiseDb] within ~17 ms. A bass
///   note's slow swell or an 808's wobble does not.
/// - **It clears where the bass was** — at least [_riseDb] over a baseline
///   that trails the level by ~90 ms. Sharp notches are common (a kick's tail
///   cancelling the bassline, sidechain ducking); their recovery rises fast,
///   but only back to the baseline, so it is not a hit.
/// - **It is loud for this song** — within [_gateDb] of the loudest bass of
///   the last few seconds, and above an absolute floor.
/// - **It is not the same hit** — [_refractory] apart, and once a hit fires
///   the baseline starts just under its peak, so its own tail cannot re-arm.
///
/// # Firing early, then topping up
///
/// A hit is reported the moment it crosses the threshold, so the picture can
/// move with the sound, then *topped up* while its attack keeps rising (up to
/// [_attackWindow]): [BassHit.gain] carries the increase. Waiting for the peak
/// instead would cost ~30 ms of every hit — enough to see.
library;

import 'dart:math' as math;

/// A bass hit, or a rise in one already reported.
class BassHit {
  const BassHit({
    required this.age,
    required this.strength,
    required this.gain,
    required this.onset,
  });

  /// Seconds between the hit and the end of the hops it was found in — how
  /// long ago it was heard when they arrived.
  final double age;

  /// How hard it hit, 0..1, against the song's recent loudest bass.
  final double strength;

  /// How much this report adds: the whole [strength] when the hit starts, the
  /// increase when its attack keeps rising.
  final double gain;

  /// Whether this report starts a hit, rather than topping one up.
  final bool onset;
}

/// Hops averaged into one level: ~23 ms, long enough to hold a full cycle of
/// a 45 Hz 808 so its waveform does not ripple the level.
const int _window = 4;

/// How far back "sharply" looks, in hops (~17 ms).
const int _fastHops = 3;

const double _fastRiseDb = 3.0;
const double _riseDb = 3.5;
const double _gateDb = 22.0;
const double _floorDb = -58.0;

/// Strength spans this many dB below the recent loudest bass: a hit that
/// loud is 1, one this much quieter is 0.
const double _rangeDb = 14.0;

const double _minStrength = 0.08;
const double _refractory = 0.11;
const double _attackWindow = 0.04;
const double _baseTau = 0.09;
const double _settleDb = 3.0;

/// How fast "the loudest bass lately" forgets, so a quiet verse after a loud
/// drop still gets full-strength hits within a few seconds.
const double _peakReleaseDbPerSecond = 3.0;

/// Finds bass hits in a stream of low-band energy.
///
/// Fed hops: the mean square of the signal below ~150 Hz over consecutive
/// slices of ~5.8 ms, as the native visualizer tap measures them.
class BassBeat {
  final List<double> _win = List<double>.filled(_window, 0);
  int _winAt = 0;
  double _winSum = 0;

  final List<double> _recent = List<double>.filled(_fastHops, -120);
  int _recentAt = 0;

  double? _base;
  double _peak = -120;
  double _clock = 0;
  double _lastOnset = -1e9;
  double _level = 0;

  // The hit whose attack is still rising, if any.
  double? _openAt;
  double _openBest = 0;
  double _openReported = 0;

  /// The bass right now, 0..1 on the same scale as [BassHit.strength].
  double get level => _level;

  /// Feeds [hops] (oldest first), each [hopSeconds] long, and returns the hits
  /// they hold, oldest first.
  List<BassHit> add(List<double> hops, double hopSeconds) {
    List<BassHit>? hits;
    final n = hops.length;
    for (var i = 0; i < n; i++) {
      final hit = _step(hops[i], hopSeconds);
      if (hit != null) {
        (hits ??= <BassHit>[]).add(
          BassHit(
            age: (n - 1 - i) * hopSeconds,
            strength: hit.$1,
            gain: hit.$2,
            onset: hit.$3,
          ),
        );
      }
    }
    return hits ?? const [];
  }

  (double, double, bool)? _step(double meanSquare, double hop) {
    final e = meanSquare.isFinite && meanSquare > 0 ? meanSquare : 0.0;
    _winSum += e - _win[_winAt];
    _win[_winAt] = e;
    _winAt = (_winAt + 1) % _window;
    final db = 10 * math.log(math.max(_winSum, 0) / _window + 1e-12) / math.ln10;

    var lowest = _recent[0];
    for (var k = 1; k < _fastHops; k++) {
      if (_recent[k] < lowest) lowest = _recent[k];
    }
    final fastRise = db - lowest;
    _recent[_recentAt] = db;
    _recentAt = (_recentAt + 1) % _fastHops;

    _clock += hop;
    final base = _base ??= db;
    _peak = db > _peak
        ? db
        : math.max(db, _peak - _peakReleaseDbPerSecond * hop);
    _level = _strengthOf(db);

    (double, double, bool)? out;
    final openAt = _openAt;
    if (openAt != null) {
      if (db > _openBest && _clock - openAt <= _attackWindow) {
        _openBest = db;
        final s = _strengthOf(db);
        if (s > _openReported) {
          out = (s, s - _openReported, false);
          _openReported = s;
        }
      } else {
        _openAt = null;
        _base = math.max(base, _openBest - _settleDb);
      }
    }
    if (_openAt == null &&
        out == null &&
        db - _base! > _riseDb &&
        fastRise >= _fastRiseDb &&
        db > _peak - _gateDb &&
        db > _floorDb &&
        _clock - _lastOnset > _refractory) {
      final s = _strengthOf(db);
      if (s >= _minStrength) {
        _openAt = _clock;
        _openBest = db;
        _openReported = s;
        _lastOnset = _clock;
        out = (s, s, true);
      }
    }
    if (_openAt == null) {
      _base = _base! + (db - _base!) * (1 - math.exp(-hop / _baseTau));
    }
    return out;
  }

  double _strengthOf(double db) =>
      ((db - (_peak - _rangeDb)) / _rangeDb).clamp(0.0, 1.0);

  /// Forgets the song: a seek or a new track starts from nothing.
  void reset() {
    _win.fillRange(0, _window, 0);
    _winAt = 0;
    _winSum = 0;
    _recent.fillRange(0, _fastHops, -120);
    _recentAt = 0;
    _base = null;
    _peak = -120;
    _clock = 0;
    _lastOnset = -1e9;
    _level = 0;
    _openAt = null;
  }
}
