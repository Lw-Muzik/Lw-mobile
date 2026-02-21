package x.a.zix;

import android.util.Log;
import androidx.annotation.NonNull;
import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.audio.BaseAudioProcessor;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * Media3 AudioProcessor that processes PCM audio through a native C++ DSP engine.
 * Supports reverb (Freeverb), stereo expansion (M/S), and crossfeed (BS2B).
 *
 * Extends BaseAudioProcessor which handles all buffer management correctly
 * (replaceOutputBuffer, getOutput, hasPendingOutput, etc.)
 *
 * Singleton — registered once during app init, discovered by just_audio via reflection.
 */
public class RoomEffectsProcessor extends BaseAudioProcessor {
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

    private RoomEffectsProcessor() {
        // Singleton
    }

    // ---- BaseAudioProcessor overrides ----

    @Override
    protected AudioFormat onConfigure(AudioFormat inputAudioFormat)
            throws UnhandledAudioFormatException {
        int encoding = inputAudioFormat.encoding;
        if (encoding != C.ENCODING_PCM_16BIT && encoding != C.ENCODING_PCM_FLOAT) {
            throw new UnhandledAudioFormatException(inputAudioFormat);
        }
        if (inputAudioFormat.channelCount != 2) {
            // Only process stereo; pass through other channel counts
            Log.w(TAG, "Non-stereo audio (" + inputAudioFormat.channelCount + "ch), passing through");
            return AudioFormat.NOT_SET;
        }

        Log.i(TAG, "Configured: " + inputAudioFormat.sampleRate + "Hz, " +
            inputAudioFormat.channelCount + "ch, encoding=" + encoding);
        // Output format matches input (in-place processing)
        return inputAudioFormat;
    }

    @Override
    public void queueInput(ByteBuffer inputBuffer) {
        if (!inputBuffer.hasRemaining()) return;

        int remaining = inputBuffer.remaining();
        int encoding = inputAudioFormat.encoding;
        int bytesPerSample = (encoding == C.ENCODING_PCM_FLOAT) ? 4 : 2;
        int numFrames = remaining / (bytesPerSample * 2); // stereo = 2 channels

        if (numFrames <= 0) {
            inputBuffer.position(inputBuffer.limit());
            return;
        }

        // Use BaseAudioProcessor's buffer management: allocates or reuses internal buffer
        ByteBuffer outputBuffer = replaceOutputBuffer(remaining);

        // Copy input to output buffer
        outputBuffer.put(inputBuffer);
        outputBuffer.flip();

        // Process through native DSP engine (in-place on outputBuffer)
        if (nativeHandle != 0) {
            if (encoding == C.ENCODING_PCM_FLOAT) {
                nativeProcessFloat(nativeHandle, outputBuffer, numFrames);
            } else {
                nativeProcessShort(nativeHandle, outputBuffer, numFrames);
            }
        }
    }

    @Override
    protected void onFlush() {
        // (Re)initialize native engine with current format
        if (inputAudioFormat != AudioFormat.NOT_SET) {
            if (nativeHandle != 0) {
                nativeReinit(nativeHandle, inputAudioFormat.sampleRate,
                    inputAudioFormat.channelCount);
            } else {
                nativeHandle = nativeCreate(inputAudioFormat.sampleRate,
                    inputAudioFormat.channelCount);
            }
        }
    }

    @Override
    protected void onReset() {
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
