/// What to do when the player rejects the track it was handed.
///
/// A streamed track's URL is not a stable address. It is single-use, it expires
/// in about six hours, and — measured 2026-08-14 — whether it will serve a byte
/// at all is decided when the *session* that resolved it was minted: roughly
/// four InnerTube sessions in ten are issued stream urls that answer
/// `playabilityStatus: OK` and then 403 the open-ended GET a player opens with.
///
/// Nothing before playback can tell those apart. The 403 from ExoPlayer is the
/// only evidence that exists, which is what makes this file necessary: the
/// player is the app's only working test of whether a url is real.
///
/// So a source error here is an ordinary event, not an exceptional one, and the
/// answer to it is to draw a new session and ask again — see
/// `YtMusicRepository.resetSession`. A few draws make a bad one unlikely
/// (0.4⁴ ≈ 2.6%); an unbounded number would be a queue stuck on one track.
library;

/// How many fresh sessions to spend on one track before moving on.
///
/// Four draws at the measured ~40% gated rate leaves about a 2.6% chance of
/// giving up on a track that would have played, at a cost of a few seconds.
/// Higher is a longer stall on a track that is genuinely gone; lower starts
/// skipping music that was only unlucky.
const maxRescueAttempts = 3;

/// The three things worth doing about a track that would not open.
enum PlaybackRecovery {
  /// Draw a new session, ask YouTube for a new URL, load the track again.
  reResolve,

  /// Give up on this track and advance. Better a gap than silence.
  skip,

  /// Nothing left to advance to.
  stop,
}

/// Decides between them.
///
/// [isStream] — whether a new URL is even obtainable. A local file that will
/// not open will not open differently next time.
/// [attempts] — how many rescues this track has already had.
/// [hasNext] — whether there is anywhere to skip to.
PlaybackRecovery recoveryFor({
  required bool isStream,
  required int attempts,
  required bool hasNext,
}) {
  // Checked before [hasNext]: the last track in a queue is still worth
  // re-resolving, and testing "is there a next" first would quietly deny it
  // the retries every other track gets.
  if (isStream && attempts < maxRescueAttempts) return PlaybackRecovery.reResolve;
  return hasNext ? PlaybackRecovery.skip : PlaybackRecovery.stop;
}
