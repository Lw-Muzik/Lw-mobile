package com.ryanheise.just_audio;

import androidx.media3.exoplayer.audio.AudioSink;
import androidx.media3.exoplayer.audio.ForwardingAudioSink;

import java.nio.ByteBuffer;

/**
 * Reports stream changes and buffer media times to {@link StemSinkListener}
 * processors, and the playback clock to {@link SinkClockListener} ones, then
 * forwards everything to the real sink unchanged.
 *
 * <p>The renderer calls {@link #setOutputStreamOffsetUs} right after the last
 * buffer of one stream and before the first of the next; buffers carry
 * {@code presentationTimeUs = mediaTimeUs + outputStreamOffsetUs} (see the
 * AudioSink javadoc).
 */
final class StemAwareAudioSink extends ForwardingAudioSink {
    private final StemSinkListener[] listeners;
    private final SinkClockListener[] clockListeners;
    private long outputStreamOffsetUs;

    StemAwareAudioSink(AudioSink sink, StemSinkListener[] listeners, SinkClockListener[] clockListeners) {
        super(sink);
        this.listeners = listeners;
        this.clockListeners = clockListeners;
    }

    @Override
    public void setOutputStreamOffsetUs(long outputStreamOffsetUs) {
        this.outputStreamOffsetUs = outputStreamOffsetUs;
        for (StemSinkListener l : listeners) l.onSinkStreamChange();
        super.setOutputStreamOffsetUs(outputStreamOffsetUs);
    }

    @Override
    public boolean handleBuffer(ByteBuffer buffer, long presentationTimeUs, int encodedAccessUnitCount)
            throws InitializationException, WriteException {
        final long mediaTimeUs = presentationTimeUs - outputStreamOffsetUs;
        for (StemSinkListener l : listeners) l.onSinkBuffer(mediaTimeUs);
        long playingUs = CURRENT_POSITION_NOT_SET;
        boolean asked = false;
        for (SinkClockListener l : clockListeners) {
            if (!l.wantsSinkClock()) continue;
            if (!asked) {
                playingUs = getCurrentPositionUs(false);
                asked = true;
            }
            l.onSinkClock(presentationTimeUs, playingUs);
        }
        return super.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount);
    }
}
