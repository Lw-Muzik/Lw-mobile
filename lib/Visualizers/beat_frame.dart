/// One tick of the native tap's bass report, as `FFTVisualizer::computeBeat`
/// writes it (Android) and HypeAudioTap mirrors it (iOS):
///
/// ```text
/// [0] format (1)   [1] sample rate   [2] hop seconds   [3] synced (1/0)
/// [4] hop count n  [5 .. 5+n)  mean square below ~150 Hz per hop
/// [5+n] band count m           [6+n .. 6+n+m)  band levels, dBFS
/// ```
library;

import 'dart:typed_data';

class BeatFrame {
  const BeatFrame({
    required this.sampleRate,
    required this.hopSeconds,
    required this.synced,
    required this.hops,
    required this.bandsDb,
  });

  final double sampleRate;
  final double hopSeconds;

  /// Whether the hops are timed to what is being heard. False when the native
  /// side has no playback clock (iOS; Android before the first buffer plays)
  /// and reads the newest audio instead.
  final bool synced;

  /// Mean square of the signal below ~150 Hz, one per hop, oldest first.
  final Float32List hops;

  /// The 64 power-curve bands' levels in dBFS where the hops end, or empty.
  final Float32List bandsDb;

  /// Reads a frame, or null if [data] is not one this code understands.
  static BeatFrame? parse(Object? data) {
    final Float32List f;
    if (data is Float32List) {
      f = data;
    } else if (data is List) {
      f = Float32List.fromList([for (final v in data) (v as num).toDouble()]);
    } else {
      return null;
    }
    if (f.length < 6 || f[0] != 1) return null;
    final n = f[4].toInt();
    if (n < 0 || f.length < 6 + n) return null;
    final m = f[5 + n].toInt();
    if (m < 0 || f.length < 6 + n + m) return null;
    final hopSeconds = f[2].toDouble();
    if (!(hopSeconds > 0)) return null;
    return BeatFrame(
      sampleRate: f[1].toDouble(),
      hopSeconds: hopSeconds,
      synced: f[3] != 0,
      hops: Float32List.sublistView(f, 5, 5 + n),
      bandsDb: Float32List.sublistView(f, 6 + n, 6 + n + m),
    );
  }
}
