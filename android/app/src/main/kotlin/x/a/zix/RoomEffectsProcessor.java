package x.a.zix;

import android.util.Log;
import androidx.annotation.NonNull;
import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.Format;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * Media3 AudioProcessor that processes PCM audio through a native C++ DSP engine.
 * Supports reverb (FDN), stereo expansion (M/S), and crossfeed (BS2B).
 *
 * Singleton — registered once during app init, discovered by just_audio via reflection.
 */
public class RoomEffectsProcessor implements AudioProcessor {
    private static final String TAG = "RoomEffectsProcessor";

    static {
        System.loadLibrary("eq_app");
    }

    // Singleton
    private static RoomEffectsProcessor instance;

    public static RoomEffectsProcessor getInstance() {
        if (instance == null) {
            instance = new RoomEffectsProcessor();
        }
        return instance;
    }

    public static boolean hasInstance() {
        return instance != null;
    }

    // Native engine handle
    private long nativeHandle = 0;

    // Audio format state
    private AudioFormat pendingInputFormat = AudioFormat.NOT_SET;
    private AudioFormat inputFormat = AudioFormat.NOT_SET;
    private boolean inputEnded = false;

    // Output buffer
    private ByteBuffer outputBuffer = EMPTY_BUFFER;

    private RoomEffectsProcessor() {
        // Singleton
    }

    // ---- AudioProcessor interface ----

    @Override
    public AudioFormat configure(AudioFormat inputAudioFormat) throws UnhandledAudioFormatException {
        int encoding = inputAudioFormat.encoding;
        if (encoding != C.ENCODING_PCM_16BIT && encoding != C.ENCODING_PCM_FLOAT) {
            throw new UnhandledAudioFormatException(inputAudioFormat);
        }
        if (inputAudioFormat.channelCount != 2) {
            // Only process stereo; pass through other channel counts
            Log.w(TAG, "Non-stereo audio (" + inputAudioFormat.channelCount + "ch), passing through");
            pendingInputFormat = AudioFormat.NOT_SET;
            return inputAudioFormat;
        }

        pendingInputFormat = inputAudioFormat;
        Log.i(TAG, "Configured: " + inputAudioFormat.sampleRate + "Hz, " +
            inputAudioFormat.channelCount + "ch, encoding=" + encoding);
        return inputAudioFormat; // Output format matches input
    }

    @Override
    public boolean isActive() {
        return pendingInputFormat != AudioFormat.NOT_SET;
    }

    @Override
    public void queueInput(ByteBuffer inputBuffer) {
        if (!inputBuffer.hasRemaining()) return;

        int remaining = inputBuffer.remaining();
        int encoding = inputFormat.encoding;
        int bytesPerSample = (encoding == C.ENCODING_PCM_FLOAT) ? 4 : 2;
        int numFrames = remaining / (bytesPerSample * 2); // stereo = 2 channels

        if (numFrames <= 0) {
            inputBuffer.position(inputBuffer.limit());
            return;
        }

        // Ensure output buffer is large enough
        if (outputBuffer.capacity() < remaining) {
            outputBuffer = ByteBuffer.allocateDirect(remaining).order(ByteOrder.nativeOrder());
        } else {
            outputBuffer.clear();
        }

        // Copy input to output, then process in-place
        outputBuffer.put(inputBuffer);
        outputBuffer.flip();
        inputBuffer.position(inputBuffer.limit());

        // Process through native DSP engine
        if (nativeHandle != 0) {
            if (encoding == C.ENCODING_PCM_FLOAT) {
                nativeProcessFloat(nativeHandle, outputBuffer, numFrames);
            } else {
                nativeProcessShort(nativeHandle, outputBuffer, numFrames);
            }
        }
    }

    @Override
    public void queueEndOfStream() {
        inputEnded = true;
    }

    @Override
    @NonNull
    public ByteBuffer getOutput() {
        ByteBuffer out = outputBuffer;
        outputBuffer = EMPTY_BUFFER;
        return out;
    }

    @Override
    public boolean isEnded() {
        return inputEnded && outputBuffer == EMPTY_BUFFER;
    }

    @Override
    public void flush() {
        outputBuffer = EMPTY_BUFFER;
        inputEnded = false;
        inputFormat = pendingInputFormat;

        // (Re)initialize native engine with current format
        if (inputFormat != AudioFormat.NOT_SET) {
            if (nativeHandle != 0) {
                nativeReinit(nativeHandle, inputFormat.sampleRate, inputFormat.channelCount);
            } else {
                nativeHandle = nativeCreate(inputFormat.sampleRate, inputFormat.channelCount);
            }
        }
    }

    @Override
    public void reset() {
        flush();
        pendingInputFormat = AudioFormat.NOT_SET;
        inputFormat = AudioFormat.NOT_SET;
        if (nativeHandle != 0) {
            nativeDestroy(nativeHandle);
            nativeHandle = 0;
        }
    }

    // ---- Public API (called from MainActivity via MethodChannel) ----

    public void setReverbEnabled(boolean enabled) {
        if (nativeHandle != 0) nativeSetReverbEnabled(nativeHandle, enabled);
    }

    public void setRoomSize(float v) {
        if (nativeHandle != 0) nativeSetRoomSize(nativeHandle, v);
    }

    public void setDecay(float v) {
        if (nativeHandle != 0) nativeSetDecay(nativeHandle, v);
    }

    public void setDamping(float v) {
        if (nativeHandle != 0) nativeSetDamping(nativeHandle, v);
    }

    public void setPreDelay(float ms) {
        if (nativeHandle != 0) nativeSetPreDelay(nativeHandle, ms);
    }

    public void setDiffusion(float v) {
        if (nativeHandle != 0) nativeSetDiffusion(nativeHandle, v);
    }

    public void setReverbWetDry(float v) {
        if (nativeHandle != 0) nativeSetReverbWetDry(nativeHandle, v);
    }

    public void setStereoExpandEnabled(boolean enabled) {
        if (nativeHandle != 0) nativeSetStereoExpandEnabled(nativeHandle, enabled);
    }

    public void setStereoWidth(float width) {
        if (nativeHandle != 0) nativeSetStereoWidth(nativeHandle, width);
    }

    public void setCrossfeedEnabled(boolean enabled) {
        if (nativeHandle != 0) nativeSetCrossfeedEnabled(nativeHandle, enabled);
    }

    public void setCrossfeedParams(float cutoffHz, float feedLevelDb) {
        if (nativeHandle != 0) nativeSetCrossfeedParams(nativeHandle, cutoffHz, feedLevelDb);
    }

    // ---- Native methods ----

    private native long nativeCreate(int sampleRate, int channels);
    private native void nativeDestroy(long handle);
    private native void nativeReset(long handle);
    private native void nativeReinit(long handle, int sampleRate, int channels);

    private native void nativeProcessFloat(long handle, ByteBuffer buffer, int numFrames);
    private native void nativeProcessShort(long handle, ByteBuffer buffer, int numFrames);

    private native void nativeSetReverbEnabled(long handle, boolean enabled);
    private native void nativeSetRoomSize(long handle, float v);
    private native void nativeSetDecay(long handle, float v);
    private native void nativeSetDamping(long handle, float v);
    private native void nativeSetPreDelay(long handle, float ms);
    private native void nativeSetDiffusion(long handle, float v);
    private native void nativeSetReverbWetDry(long handle, float v);

    private native void nativeSetStereoExpandEnabled(long handle, boolean enabled);
    private native void nativeSetStereoWidth(long handle, float width);

    private native void nativeSetCrossfeedEnabled(long handle, boolean enabled);
    private native void nativeSetCrossfeedParams(long handle, float cutoffHz, float feedLevelDb);
}
