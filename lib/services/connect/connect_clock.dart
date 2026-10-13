/// This phone's view of the hub's clock (contract §3.7).
///
/// A visualiser frame says *when* its audio is heard in hub time, so the
/// browser can draw it on the beat whatever the network lag. That only works if
/// this phone knows how far its own clock is from the hub's.
///
/// # One sample
///
/// `ping` goes out at local time `sent`, `pong` comes back at `received` with
/// the hub's `serverTime`. The hub answered somewhere in between; assuming the
/// middle, the hub clock reads `serverTime` when ours reads
/// `(sent + received) / 2`, so
///
///     offset = serverTime - (sent + received) / 2
///
/// The error of that assumption is at most half the round trip, which is why
/// the best sample is the one with the *smallest* round trip: a pong that sat
/// in a radio queue for 400 ms says little, one that took 30 ms says a lot.
///
/// # Keeping a few
///
/// Samples are taken on every `welcome` and every ~10 s after. The last
/// [window] are kept and the fastest wins, so a single slow exchange cannot
/// move the estimate and an old good one ages out after [window] samples
/// instead of pinning the offset forever (device clocks drift, and the user can
/// change theirs).
library;

import 'package:clock/clock.dart';

class HubClock {
  HubClock({this.window = 5, this.maxRoundTripMs = 10000});

  /// How many recent samples are compared.
  final int window;

  /// A round trip longer than this is not a measurement of anything.
  final int maxRoundTripMs;

  final List<_Sample> _samples = [];
  int? _seededOffset;

  /// Hub time minus local time, in milliseconds; null before anything is known.
  int? get offsetMs => _best?.offsetMs ?? _seededOffset;

  /// Round trip of the sample the offset comes from; null with no real sample.
  int? get roundTripMs => _best?.roundTripMs;

  /// Whether a ping/pong exchange has been measured (a seed does not count).
  bool get isMeasured => _samples.isNotEmpty;

  /// The hub's epoch milliseconds right now. Before any measurement this is the
  /// local clock — wrong by the offset, but never absent.
  int nowMs() => clock.now().millisecondsSinceEpoch + (offsetMs ?? 0);

  /// Records one ping/pong exchange. Returns false when it was unusable
  /// (negative or absurd round trip, e.g. the local clock was set mid-flight).
  bool addSample({
    required int sentMs,
    required int receivedMs,
    required int serverTimeMs,
  }) {
    final roundTrip = receivedMs - sentMs;
    if (roundTrip < 0 || roundTrip > maxRoundTripMs) return false;
    final offset = (serverTimeMs - (sentMs + receivedMs) / 2).round();
    _samples.add(_Sample(offset, roundTrip));
    while (_samples.length > window) {
      _samples.removeAt(0);
    }
    return true;
  }

  /// A first guess from `welcome`, used only until a real sample arrives: the
  /// hello-to-welcome trip includes token verification, so it is not a
  /// measurement, but a clock that is merely off by that is better than one that
  /// is off by the whole offset.
  void seedFromWelcome({required int serverTimeMs, required int receivedMs}) {
    _seededOffset ??= serverTimeMs - receivedMs;
  }

  void clear() {
    _samples.clear();
    _seededOffset = null;
  }

  /// The fastest of the kept samples; on a tie the newest.
  _Sample? get _best {
    _Sample? best;
    for (final sample in _samples) {
      if (best == null || sample.roundTripMs <= best.roundTripMs) best = sample;
    }
    return best;
  }
}

class _Sample {
  const _Sample(this.offsetMs, this.roundTripMs);
  final int offsetMs;
  final int roundTripMs;
}
