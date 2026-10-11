package com.ryanheise.just_audio;

import androidx.media3.exoplayer.audio.AudioSink;
import androidx.media3.exoplayer.audio.ForwardingAudioSink;

import java.nio.ByteBuffer;

/**
 * Reports stream changes and buffer media times to {@link StemSinkListener}
 * processors, then forwards everything to the real sink unchanged.
 *
 * <p>The renderer calls {@link #setOutputStreamOffsetUs} right after the last
 * buffer of one stream and before the first of the next; buffers carry
 * {@code presentationTimeUs = mediaTimeUs + outputStreamOffsetUs} (see the
 * AudioSink javadoc).
 */
final class StemAwareAudioSink extends ForwardingAudioSink {
    private final StemSinkListener[] listeners;
    private long outputStreamOffsetUs;
    private long tmpLastLog; // TEMP-VIZLEAD

    StemAwareAudioSink(AudioSink sink, StemSinkListener[] listeners) {
        super(sink);
        this.listeners = listeners;
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
        // TEMP-VIZLEAD
        long tmpNow = System.nanoTime();
        if (tmpNow - tmpLastLog > 1_000_000_000L) {
            tmpLastLog = tmpNow;
            long tmpPos = getCurrentPositionUs(false);
            android.util.Log.i("VizLead", "buffer=" + presentationTimeUs + " playing=" + tmpPos
                + " lead_ms=" + ((presentationTimeUs - tmpPos) / 1000) + " bytes=" + buffer.remaining());
        }
        return super.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount);
    }
}
