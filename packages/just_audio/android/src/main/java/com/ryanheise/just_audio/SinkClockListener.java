package com.ryanheise.just_audio;

/**
 * Implemented by an app AudioProcessor that lines what it processes up with
 * what is being heard (Hype's VisualizerTapProcessor).
 *
 * <p>A processor runs as its buffer is handed to the AudioTrack — a quarter of
 * a second or more before that audio leaves the speaker. The sink knows both
 * ends: the presentation time of each buffer it is given, and the position it
 * is playing out, which accounts for the track's buffer and the output's
 * latency (it is what keeps video lip-synced).
 */
public interface SinkClockListener {
    /** Playback thread, cheap: whether the clock is wanted right now. */
    boolean wantsSinkClock();

    /**
     * Playback thread: the sink is about to handle the buffer presented at
     * {@code presentationTimeUs} while playing out {@code playingPositionUs}.
     * Both are in the renderer's timeline; {@code playingPositionUs} is
     * {@link androidx.media3.exoplayer.audio.AudioSink#CURRENT_POSITION_NOT_SET}
     * until the track is playing.
     */
    void onSinkClock(long presentationTimeUs, long playingPositionUs);
}
