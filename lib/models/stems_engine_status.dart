/// What the native stems engine reports, parsed defensively.
///
/// Both arrive as loose maps over a platform channel, written by code this
/// side doesn't own — a field may be missing, an `int` where a `double` was
/// meant, or a state this build has never heard of. None of that may throw
/// into the UI.
library;

import 'package:flutter/foundation.dart';

enum StemsEngineState { idle, preparing, ready, unavailable, error }

@immutable
class StemsEngineStatus {
  final StemsEngineState state;

  /// Why stems are unavailable or failed: `stream` (no local copy of it yet),
  /// `fetch` (the copy couldn't be downloaded — set by the controller),
  /// `protected`, `unsupported`, `decode` or `model`. Kept as the raw string so
  /// a reason added natively later still reaches the UI as "something else".
  final String? reason;

  /// How much of the current song has been separated, 0–1.
  final double progress;

  /// How far ahead of the playhead separation has got, in seconds.
  final double aheadSeconds;

  /// The engine's identity for the track it is working on.
  final String? trackKey;

  /// The same for the item the player has queued after it, when it knows —
  /// so a stream's copy can be fetched before that item starts.
  final String? nextKey;

  const StemsEngineStatus({
    required this.state,
    this.reason,
    this.progress = 0,
    this.aheadSeconds = 0,
    this.trackKey,
    this.nextKey,
  });

  static const idle = StemsEngineStatus(state: StemsEngineState.idle);

  /// What the tab shows between asking the engine to start and its first
  /// answer — the original is playing meanwhile, which is what "preparing"
  /// means to the person looking at it.
  static const starting = StemsEngineStatus(state: StemsEngineState.preparing);

  factory StemsEngineStatus.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return idle;
    final state = switch (map['state']) {
      'preparing' => StemsEngineState.preparing,
      'ready' => StemsEngineState.ready,
      'unavailable' => StemsEngineState.unavailable,
      'error' => StemsEngineState.error,
      _ => StemsEngineState.idle,
    };
    final reason = map['reason'];
    final trackKey = map['trackKey'];
    final nextKey = map['nextKey'];
    return StemsEngineStatus(
      state: state,
      reason: reason is String && reason.isNotEmpty ? reason : null,
      progress: _fraction(map['progress']),
      aheadSeconds: _nonNegative(map['aheadSeconds']),
      trackKey: trackKey is String ? trackKey : null,
      nextKey: nextKey is String && nextKey.isNotEmpty ? nextKey : null,
    );
  }

  bool get isReady => state == StemsEngineState.ready;

  @override
  bool operator ==(Object other) =>
      other is StemsEngineStatus &&
      other.state == state &&
      other.reason == reason &&
      other.progress == progress &&
      other.aheadSeconds == aheadSeconds &&
      other.trackKey == trackKey &&
      other.nextKey == nextKey;

  @override
  int get hashCode =>
      Object.hash(state, reason, progress, aheadSeconds, trackKey, nextKey);

  @override
  String toString() =>
      'StemsEngineStatus(${state.name}, reason: $reason, '
      'progress: $progress, ahead: ${aheadSeconds}s, track: $trackKey, '
      'next: $nextKey)';
}

/// The one-time speed test that decides whether this phone gets live stems.
@immutable
class StemsBenchmark {
  /// Slowest real-time factor that still keeps separation ahead of playback
  /// with headroom for the player, the UI and a warm phone: separating one
  /// second of audio must take no more than 0.6 s.
  static const double maxRtf = 0.6;

  final bool ok;

  /// Seconds of work per second of audio. Lower is faster.
  final double rtf;

  final int millis;
  final String? error;

  const StemsBenchmark({
    required this.ok,
    required this.rtf,
    required this.millis,
    this.error,
  });

  factory StemsBenchmark.fromMap(Map<dynamic, dynamic> map) {
    final ok = map['ok'];
    final rtf = map['rtf'];
    final millis = map['millis'];
    final error = map['error'];
    return StemsBenchmark(
      ok: ok == true,
      rtf: rtf is num ? rtf.toDouble() : double.nan,
      millis: millis is num ? millis.toInt() : 0,
      error: error is String && error.isNotEmpty ? error : null,
    );
  }

  /// Whether the phone is fast enough. A measurement that came back broken
  /// (negative, NaN) counts as "no": the cost of a wrong yes is a song that
  /// stutters, the cost of a wrong no is one "Test again" tap.
  bool get supported => ok && rtf.isFinite && rtf >= 0 && rtf <= maxRtf;

  Map<String, Object?> toJson() => {
    'ok': ok,
    'rtf': rtf.isFinite ? rtf : null,
    'millis': millis,
    if (error != null) 'error': error,
  };

  @override
  bool operator ==(Object other) =>
      other is StemsBenchmark &&
      other.ok == ok &&
      (other.rtf == rtf || (other.rtf.isNaN && rtf.isNaN)) &&
      other.millis == millis &&
      other.error == error;

  @override
  int get hashCode => Object.hash(ok, rtf.isNaN ? null : rtf, millis, error);

  @override
  String toString() =>
      'StemsBenchmark(ok: $ok, rtf: $rtf, millis: $millis, error: $error)';
}

double _fraction(Object? value) {
  if (value is! num) return 0;
  final v = value.toDouble();
  if (!v.isFinite) return 0;
  return v.clamp(0.0, 1.0);
}

double _nonNegative(Object? value) {
  if (value is! num) return 0;
  final v = value.toDouble();
  if (!v.isFinite || v < 0) return 0;
  return v;
}
