package com.ryanheise.just_audio;

/**
 * Implemented by an app AudioProcessor (Hype's RoomEffectsProcessor) that needs
 * to know which queue item, and which media time of it, the PCM it processes
 * belongs to — live stem separation aligns its own decode of the track to it.
 *
 * <p>Media3 1.4 does not give audio processors this information, so the player
 * wraps its AudioSink ({@link StemAwareAudioSink}) and reports it from there.
 */
public interface StemSinkListener {
    /** Playback thread: the following buffers belong to another stream (queue item). */
    void onSinkStreamChange();

    /** Playback thread: media time (µs, within its item) of the buffer about to be processed. */
    void onSinkBuffer(long mediaTimeUs);

    /** Main thread: URIs of the player's current and next queue items (null when none). */
    void onTrackKeys(String currentUri, String nextUri);
}
