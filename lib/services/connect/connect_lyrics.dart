/// Answering the `lyrics` rpc (contract §3.8, v1.1).
///
/// A browser controller shows the lyrics of whatever this phone is playing. It
/// asks, the phone answers with what its own player screen would show, using
/// the same resolver (cache first), so the two never disagree.
///
/// # The 10-second rule
///
/// The hub gives an rpc 15 s. A lookup can outlast that (fingerprinting a weak
/// tag, a slow LRCLIB), so after [lyricsAnswerWindow] the answer is
/// `found:false` *now* while the lookup keeps running; the resolver caches what
/// it finds and the controller's next ask (the web re-asks after 8 s) is served
/// from there. Answering late would only buy a `timeout` error.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'package:eq_app/models/lyrics_model.dart';
import 'package:eq_app/services/connect/connect_protocol.dart';

/// How long a lookup may take before the answer is `found:false`.
const Duration lyricsAnswerWindow = Duration(seconds: 10);

/// The lyrics resolver, as the rpc handler reads it.
abstract interface class ConnectLyricsSource {
  /// Lyrics for [song]; null when none exist. The lookup must keep running
  /// (and cache its result) if the caller stops waiting.
  Future<LyricsData?> lyricsFor(SongModel song);
}

/// The wire form of [data] for [track].
///
/// * `synced` means *every* line has a start, so a mixed list (some timed, some
///   not) is sent unsynced rather than half-timed.
/// * Start times are track time: the LRC `[offset:]` the player screen adds to
///   its clock is taken off here, so the controller needs no knowledge of it.
/// * `words` only when the resolver really has word timing.
/// * Blank lines stay as `text: ""` — they are the instrumental gaps.
LyricsResult lyricsResultOf(TrackRef? track, LyricsData? data) {
  if (data == null || !data.lines.any((l) => l.text.trim().isNotEmpty)) {
    return LyricsResult.none(track);
  }
  final synced = data.isSynced && data.lines.every((l) => l.timestamp != null);
  final offset = synced ? data.offsetMs : 0;
  int shifted(Duration d) {
    final ms = d.inMilliseconds - offset;
    return ms < 0 ? 0 : ms;
  }

  return LyricsResult(
    track: track,
    found: true,
    synced: synced,
    source: data.source,
    lines: [
      for (final line in data.lines)
        ConnectLyricLine(
          startMs: synced ? shifted(line.timestamp!) : null,
          text: line.text.trim(),
          words: synced && line.words != null && line.words!.isNotEmpty
              ? [
                  for (final w in line.words!)
                    ConnectLyricWord(
                      startMs: shifted(w.startTime),
                      endMs: shifted(w.endTime),
                      text: w.text,
                    ),
                ]
              : null,
        ),
    ],
  );
}

/// Looks up [song]'s lyrics and maps them, never waiting longer than [window].
Future<LyricsResult> answerLyrics({
  required TrackRef? track,
  required SongModel? song,
  required ConnectLyricsSource source,
  Duration window = lyricsAnswerWindow,
}) async {
  if (song == null) return const LyricsResult.none(null);
  try {
    final data = await source.lyricsFor(song).timeout(window);
    return lyricsResultOf(track, data);
  } on TimeoutException {
    // Not cancelled: the lookup carries on and the next ask finds it.
    return LyricsResult.none(track);
  } catch (e) {
    debugPrint('Hype Connect: lyrics lookup failed: $e');
    return LyricsResult.none(track);
  }
}
