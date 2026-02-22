package x.a.zix;

import android.util.Log;
import androidx.annotation.NonNull;
import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.audio.BaseAudioProcessor;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * Media3 AudioProcessor that processes PCM audio through a native C++ DSP engine.
 * Supports reverb (Freeverb), stereo expansion (M/S), and crossfeed (BS2B).
 *
 * Each ExoPlayer instance gets its own processor via {@link #createPlayerInstance()},
 * ensuring independent buffer management and native DSP state. This is critical for
 * crossfade where two players process audio concurrently — a shared singleton would
 * corrupt BaseAudioProcessor's internal buffer and the native engine state.
 *
 * Parameter changes from the UI are broadcast to all player instances via the
 * static broadcast methods. Cached params are applied when a new native handle
 * is created (in onFlush) so late-initialized players get current settings.
 */
public class RoomEffectsProcessor extends BaseAudioProcessor {
    private static final String TAG = "RoomEffectsProcessor";

    static {
        System.loadLibrary("eq_app");
    }

    // All player-attached instances — each ExoPlayer gets its own
    private static final CopyOnWriteArrayList<RoomEffectsProcessor> playerInstances =
            new CopyOnWriteArrayList<>();

    // Cached params — applied to new native handles on creation
    private static volatile boolean cachedReverbEnabled = false;
    private static volatile float cachedRoomSize = 0.5f;
    private static volatile float cachedDecay = 0.5f;
    private static volatile float cachedDamping = 0.5f;
    private static volatile float cachedPreDelay = 0f;
    private static volatile float cachedDiffusion = 0.5f;
    private static volatile float cachedReverbWetDry = 0.3f;
    private static volatile boolean cachedStereoExpandEnabled = false;
    private static volatile float cachedStereoWidth = 1.0f;
    private static volatile boolean cachedCrossfeedEnabled = false;
    private static volatile float cachedCrossfeedCutoff = 700f;
    private static volatile float cachedCrossfeedFeed = 4.5f;

    // Cached EQ params
    private static volatile boolean cachedEqEnabled = false;
    private static volatile float cachedPreampGain = 0f;
    private static final float[] cachedGraphicGains = new float[32]; // all 0.0f
    private static final float[] cachedParametricFreqs = new float[32];
    private static final float[] cachedParametricGains = new float[32];
    private static final float[] cachedParametricQs = new float[32];
    // Cached MBC params
    private static volatile boolean cachedMbcEnabled = false;
    private static volatile float cachedMbcPreGain = 0f;
    private static volatile float cachedMbcNoiseGate = -70f;
    private static volatile float cachedMbcKneeWidth = 8f;
    private static volatile float cachedMbcExpanderRatio = 2f;

    static {
        // Initialize parametric defaults
        for (int i = 0; i < 32; i++) {
            cachedParametricFreqs[i] = 1000f;
            cachedParametricQs[i] = 1.4f;
        }
    }

    /**
     * Called from MainActivity.onCreate() to ensure the native library is loaded.
     * No longer creates a singleton used in the audio pipeline.
     */
    public static RoomEffectsProcessor getInstance() {
        // Just ensure class is loaded (static block loads native lib).
        // Return a dummy instance for backward compat — not used in audio pipeline.
        return new RoomEffectsProcessor();
    }

    public static boolean hasInstance() {
        return !playerInstances.isEmpty();
    }

    /**
     * Called by just_audio's AudioPlayer.java via reflection.
     * Each ExoPlayer gets its own processor with independent buffer state
     * and native DSP engine handle.
     */
    public static RoomEffectsProcessor createPlayerInstance() {
        RoomEffectsProcessor p = new RoomEffectsProcessor();
        playerInstances.add(p);
        Log.i(TAG, "Player instance created, total: " + playerInstances.size());
        return p;
    }

    // Native engine handle — unique per instance
    private long nativeHandle = 0;

    private RoomEffectsProcessor() {}

    // ---- BaseAudioProcessor overrides ----

    @Override
    protected AudioFormat onConfigure(AudioFormat inputAudioFormat)
            throws UnhandledAudioFormatException {
        int encoding = inputAudioFormat.encoding;
        if (encoding != C.ENCODING_PCM_16BIT && encoding != C.ENCODING_PCM_FLOAT) {
            throw new UnhandledAudioFormatException(inputAudioFormat);
        }
        if (inputAudioFormat.channelCount != 2) {
            Log.w(TAG, "Non-stereo audio (" + inputAudioFormat.channelCount + "ch), passing through");
            return AudioFormat.NOT_SET;
        }

        Log.i(TAG, "Configured: " + inputAudioFormat.sampleRate + "Hz, " +
            inputAudioFormat.channelCount + "ch, encoding=" + encoding);
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

        ByteBuffer outputBuffer = replaceOutputBuffer(remaining);
        outputBuffer.put(inputBuffer);
        outputBuffer.flip();

        // Process through this instance's native DSP engine
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
        if (inputAudioFormat != AudioFormat.NOT_SET) {
            if (nativeHandle != 0) {
                nativeReinit(nativeHandle, inputAudioFormat.sampleRate,
                    inputAudioFormat.channelCount);
            } else {
                nativeHandle = nativeCreate(inputAudioFormat.sampleRate,
                    inputAudioFormat.channelCount);
            }
            // Apply current cached params to this instance's native handle
            applyCachedParams();
        }
    }

    @Override
    protected void onReset() {
        if (nativeHandle != 0) {
            nativeDestroy(nativeHandle);
            nativeHandle = 0;
        }
    }

    /** Apply all cached params to this instance's native handle. */
    private void applyCachedParams() {
        if (nativeHandle == 0) return;
        nativeSetReverbEnabled(nativeHandle, cachedReverbEnabled);
        nativeSetRoomSize(nativeHandle, cachedRoomSize);
        nativeSetDecay(nativeHandle, cachedDecay);
        nativeSetDamping(nativeHandle, cachedDamping);
        nativeSetPreDelay(nativeHandle, cachedPreDelay);
        nativeSetDiffusion(nativeHandle, cachedDiffusion);
        nativeSetReverbWetDry(nativeHandle, cachedReverbWetDry);
        nativeSetStereoExpandEnabled(nativeHandle, cachedStereoExpandEnabled);
        nativeSetStereoWidth(nativeHandle, cachedStereoWidth);
        nativeSetCrossfeedEnabled(nativeHandle, cachedCrossfeedEnabled);
        nativeSetCrossfeedParams(nativeHandle, cachedCrossfeedCutoff, cachedCrossfeedFeed);
        // EQ state
        nativeSetEqEnabled(nativeHandle, cachedEqEnabled);
        nativeSetPreampGain(nativeHandle, cachedPreampGain);
        nativeSetGraphicAllBands(nativeHandle, cachedGraphicGains);
        nativeSetParametricAllBands(nativeHandle, cachedParametricFreqs,
                cachedParametricGains, cachedParametricQs, 32);
        // MBC state
        nativeSetMbcEnabled(nativeHandle, cachedMbcEnabled);
        nativeSetMbcPreGain(nativeHandle, cachedMbcPreGain);
        nativeSetMbcNoiseGate(nativeHandle, cachedMbcNoiseGate);
        nativeSetMbcKneeWidth(nativeHandle, cachedMbcKneeWidth);
        nativeSetMbcExpanderRatio(nativeHandle, cachedMbcExpanderRatio);
    }

    // ---- Instance methods (called on specific instance) ----

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

    // EQ instance methods
    public void setEqEnabled(boolean enabled) {
        if (nativeHandle != 0) nativeSetEqEnabled(nativeHandle, enabled);
    }

    public void setPreampGain(float dB) {
        if (nativeHandle != 0) nativeSetPreampGain(nativeHandle, dB);
    }

    public void setGraphicBandGain(int band, float dB) {
        if (nativeHandle != 0) nativeSetGraphicBandGain(nativeHandle, band, dB);
    }

    public void setGraphicAllBands(float[] gains) {
        if (nativeHandle != 0) nativeSetGraphicAllBands(nativeHandle, gains);
    }

    public void setParametricBand(int band, float freq, float gainDb, float q,
                                  int filterType, boolean enabled) {
        if (nativeHandle != 0) nativeSetParametricBand(nativeHandle, band, freq, gainDb,
                q, filterType, enabled);
    }

    public void setParametricAllBands(float[] freqs, float[] gains, float[] qs, int count) {
        if (nativeHandle != 0) nativeSetParametricAllBands(nativeHandle, freqs, gains, qs, count);
    }

    // MBC instance methods
    public void setMbcEnabled(boolean enabled) {
        if (nativeHandle != 0) nativeSetMbcEnabled(nativeHandle, enabled);
    }

    public void setMbcPreGain(float dB) {
        if (nativeHandle != 0) nativeSetMbcPreGain(nativeHandle, dB);
    }

    public void setMbcNoiseGate(float dB) {
        if (nativeHandle != 0) nativeSetMbcNoiseGate(nativeHandle, dB);
    }

    public void setMbcKneeWidth(float dB) {
        if (nativeHandle != 0) nativeSetMbcKneeWidth(nativeHandle, dB);
    }

    public void setMbcExpanderRatio(float ratio) {
        if (nativeHandle != 0) nativeSetMbcExpanderRatio(nativeHandle, ratio);
    }

    // ---- Static broadcast methods (called from MainActivity via MethodChannel) ----

    public static void broadcastReverbEnabled(boolean enabled) {
        cachedReverbEnabled = enabled;
        for (RoomEffectsProcessor p : playerInstances) p.setReverbEnabled(enabled);
    }

    public static void broadcastRoomSize(float v) {
        cachedRoomSize = v;
        for (RoomEffectsProcessor p : playerInstances) p.setRoomSize(v);
    }

    public static void broadcastDecay(float v) {
        cachedDecay = v;
        for (RoomEffectsProcessor p : playerInstances) p.setDecay(v);
    }

    public static void broadcastDamping(float v) {
        cachedDamping = v;
        for (RoomEffectsProcessor p : playerInstances) p.setDamping(v);
    }

    public static void broadcastPreDelay(float ms) {
        cachedPreDelay = ms;
        for (RoomEffectsProcessor p : playerInstances) p.setPreDelay(ms);
    }

    public static void broadcastDiffusion(float v) {
        cachedDiffusion = v;
        for (RoomEffectsProcessor p : playerInstances) p.setDiffusion(v);
    }

    public static void broadcastReverbWetDry(float v) {
        cachedReverbWetDry = v;
        for (RoomEffectsProcessor p : playerInstances) p.setReverbWetDry(v);
    }

    public static void broadcastStereoExpandEnabled(boolean enabled) {
        cachedStereoExpandEnabled = enabled;
        for (RoomEffectsProcessor p : playerInstances) p.setStereoExpandEnabled(enabled);
    }

    public static void broadcastStereoWidth(float width) {
        cachedStereoWidth = width;
        for (RoomEffectsProcessor p : playerInstances) p.setStereoWidth(width);
    }

    public static void broadcastCrossfeedEnabled(boolean enabled) {
        cachedCrossfeedEnabled = enabled;
        for (RoomEffectsProcessor p : playerInstances) p.setCrossfeedEnabled(enabled);
    }

    public static void broadcastCrossfeedParams(float cutoffHz, float feedLevelDb) {
        cachedCrossfeedCutoff = cutoffHz;
        cachedCrossfeedFeed = feedLevelDb;
        for (RoomEffectsProcessor p : playerInstances) p.setCrossfeedParams(cutoffHz, feedLevelDb);
    }

    // ---- EQ broadcast methods ----

    public static void broadcastEqEnabled(boolean enabled) {
        cachedEqEnabled = enabled;
        for (RoomEffectsProcessor p : playerInstances) p.setEqEnabled(enabled);
    }

    public static void broadcastPreampGain(float dB) {
        cachedPreampGain = dB;
        for (RoomEffectsProcessor p : playerInstances) p.setPreampGain(dB);
    }

    public static void broadcastGraphicBandGain(int band, float dB) {
        if (band >= 0 && band < 32) cachedGraphicGains[band] = dB;
        for (RoomEffectsProcessor p : playerInstances) p.setGraphicBandGain(band, dB);
    }

    public static void broadcastGraphicAllBands(float[] gains) {
        int count = Math.min(gains.length, 32);
        System.arraycopy(gains, 0, cachedGraphicGains, 0, count);
        for (RoomEffectsProcessor p : playerInstances) p.setGraphicAllBands(gains);
    }

    public static void broadcastParametricBand(int band, float freq, float gainDb,
                                               float q, int filterType, boolean enabled) {
        if (band >= 0 && band < 32) {
            cachedParametricFreqs[band] = freq;
            cachedParametricGains[band] = gainDb;
            cachedParametricQs[band] = q;
        }
        for (RoomEffectsProcessor p : playerInstances)
            p.setParametricBand(band, freq, gainDb, q, filterType, enabled);
    }

    public static void broadcastParametricAllBands(float[] freqs, float[] gains,
                                                    float[] qs, int count) {
        int n = Math.min(count, 32);
        System.arraycopy(freqs, 0, cachedParametricFreqs, 0, n);
        System.arraycopy(gains, 0, cachedParametricGains, 0, n);
        System.arraycopy(qs, 0, cachedParametricQs, 0, n);
        for (RoomEffectsProcessor p : playerInstances)
            p.setParametricAllBands(freqs, gains, qs, count);
    }

    public static float getCachedPreampGain() {
        return cachedPreampGain;
    }

    public static boolean isCachedMbcEnabled() {
        return cachedMbcEnabled;
    }

    // ---- MBC broadcast methods ----

    public static void broadcastMbcEnabled(boolean enabled) {
        cachedMbcEnabled = enabled;
        for (RoomEffectsProcessor p : playerInstances) p.setMbcEnabled(enabled);
    }

    public static void broadcastMbcPreGain(float dB) {
        cachedMbcPreGain = dB;
        for (RoomEffectsProcessor p : playerInstances) p.setMbcPreGain(dB);
    }

    public static void broadcastMbcNoiseGate(float dB) {
        cachedMbcNoiseGate = dB;
        for (RoomEffectsProcessor p : playerInstances) p.setMbcNoiseGate(dB);
    }

    public static void broadcastMbcKneeWidth(float dB) {
        cachedMbcKneeWidth = dB;
        for (RoomEffectsProcessor p : playerInstances) p.setMbcKneeWidth(dB);
    }

    public static void broadcastMbcExpanderRatio(float ratio) {
        cachedMbcExpanderRatio = ratio;
        for (RoomEffectsProcessor p : playerInstances) p.setMbcExpanderRatio(ratio);
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

    private native void nativeSetEqEnabled(long handle, boolean enabled);
    private native void nativeSetPreampGain(long handle, float dB);
    private native void nativeSetGraphicBandGain(long handle, int band, float dB);
    private native void nativeSetGraphicAllBands(long handle, float[] gains);
    private native void nativeSetParametricBand(long handle, int band, float freq,
                                                float gainDb, float q, int filterType,
                                                boolean enabled);
    private native void nativeSetParametricAllBands(long handle, float[] freqs, float[] gains,
                                                     float[] qs, int count);

    private native void nativeSetMbcEnabled(long handle, boolean enabled);
    private native void nativeSetMbcPreGain(long handle, float dB);
    private native void nativeSetMbcNoiseGate(long handle, float dB);
    private native void nativeSetMbcKneeWidth(long handle, float dB);
    private native void nativeSetMbcExpanderRatio(long handle, float ratio);
}
