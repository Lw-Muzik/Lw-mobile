package x.a.zix;

import android.os.Build;
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
    private static volatile float cachedMbcThreshold = -24f;
    private static volatile float cachedMbcRatio = 4f;
    private static volatile float cachedMbcAttackTime = 5f;
    private static volatile float cachedMbcReleaseTime = 50f;
    private static volatile float cachedMbcPostGain = 0f;

    // Cached Tone controls (bass/treble)
    private static volatile boolean cachedToneEnabled = false;
    private static volatile float cachedBassGain = 0f;
    private static volatile float cachedBassFreq = 80f;
    private static volatile float cachedBassQ = 0.707f;
    private static volatile float cachedTrebleGain = 0f;
    private static volatile float cachedTrebleFreq = 10000f;
    private static volatile float cachedTrebleQ = 0.707f;

    // Cached Limiter
    private static volatile boolean cachedLimiterEnabled = true;
    private static volatile float cachedLimiterCeiling = 0.98f;
    private static volatile float cachedLimiterRelease = 50f;
    private static volatile float cachedLimiterKnee = 6f;

    // Cached Stem mixer state
    private static volatile boolean cachedStemModeActive = false;
    private static volatile String[] cachedStemPaths = null;
    private static final float[] cachedStemVolumes = {1.0f, 1.0f, 1.0f, 1.0f};
    private static final boolean[] cachedStemMutes = {false, false, false, false};
    private static final boolean[] cachedStemSolos = {false, false, false, false};

    // Cached Speaker correction EQ (AutoEq headphone profiles)
    private static volatile boolean cachedSpeakerEqEnabled = false;
    private static volatile int cachedSpeakerBandCount = 0;
    private static final float[] cachedSpeakerEqFreqs = new float[32];
    private static final float[] cachedSpeakerEqGains = new float[32];
    private static final float[] cachedSpeakerEqQs = new float[32];
    private static final int[] cachedSpeakerEqTypes = new int[32];

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
        nativeSetMbcThreshold(nativeHandle, cachedMbcThreshold);
        nativeSetMbcRatio(nativeHandle, cachedMbcRatio);
        nativeSetMbcAttackTime(nativeHandle, cachedMbcAttackTime);
        nativeSetMbcReleaseTime(nativeHandle, cachedMbcReleaseTime);
        nativeSetMbcPostGain(nativeHandle, cachedMbcPostGain);
        // Tone controls
        nativeSetToneEnabled(nativeHandle, cachedToneEnabled);
        nativeSetBassGain(nativeHandle, cachedBassGain);
        nativeSetBassFreq(nativeHandle, cachedBassFreq);
        nativeSetBassQ(nativeHandle, cachedBassQ);
        nativeSetTrebleGain(nativeHandle, cachedTrebleGain);
        nativeSetTrebleFreq(nativeHandle, cachedTrebleFreq);
        nativeSetTrebleQ(nativeHandle, cachedTrebleQ);
        // Limiter
        nativeSetLimiterEnabled(nativeHandle, cachedLimiterEnabled);
        nativeSetLimiterCeiling(nativeHandle, cachedLimiterCeiling);
        nativeSetLimiterRelease(nativeHandle, cachedLimiterRelease);
        nativeSetLimiterKnee(nativeHandle, cachedLimiterKnee);
        // Speaker correction EQ
        nativeSetSpeakerEqEnabled(nativeHandle, cachedSpeakerEqEnabled);
        int spkCount = cachedSpeakerBandCount;
        for (int i = 0; i < spkCount; i++) {
            nativeSetSpeakerEqBand(nativeHandle, i, cachedSpeakerEqFreqs[i],
                    cachedSpeakerEqGains[i], cachedSpeakerEqQs[i],
                    cachedSpeakerEqTypes[i], true);
        }
        // Stem mixer state
        if (cachedStemPaths != null) {
            nativeLoadStems(nativeHandle, cachedStemPaths);
        }
        nativeSetStemModeActive(nativeHandle, cachedStemModeActive);
        for (int i = 0; i < 4; i++) {
            nativeSetStemVolume(nativeHandle, i, cachedStemVolumes[i]);
            nativeSetStemMute(nativeHandle, i, cachedStemMutes[i]);
            nativeSetStemSolo(nativeHandle, i, cachedStemSolos[i]);
        }
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

    public void setMbcThreshold(float dB) {
        if (nativeHandle != 0) nativeSetMbcThreshold(nativeHandle, dB);
    }

    public void setMbcRatio(float ratio) {
        if (nativeHandle != 0) nativeSetMbcRatio(nativeHandle, ratio);
    }

    public void setMbcAttackTime(float ms) {
        if (nativeHandle != 0) nativeSetMbcAttackTime(nativeHandle, ms);
    }

    public void setMbcReleaseTime(float ms) {
        if (nativeHandle != 0) nativeSetMbcReleaseTime(nativeHandle, ms);
    }

    public void setMbcPostGain(float dB) {
        if (nativeHandle != 0) nativeSetMbcPostGain(nativeHandle, dB);
    }

    // Tone control instance methods
    public void setToneEnabled(boolean enabled) {
        if (nativeHandle != 0) nativeSetToneEnabled(nativeHandle, enabled);
    }

    public void setBassGain(float dB) {
        if (nativeHandle != 0) nativeSetBassGain(nativeHandle, dB);
    }

    public void setBassFreq(float hz) {
        if (nativeHandle != 0) nativeSetBassFreq(nativeHandle, hz);
    }

    public void setBassQ(float q) {
        if (nativeHandle != 0) nativeSetBassQ(nativeHandle, q);
    }

    public void setTrebleGain(float dB) {
        if (nativeHandle != 0) nativeSetTrebleGain(nativeHandle, dB);
    }

    public void setTrebleFreq(float hz) {
        if (nativeHandle != 0) nativeSetTrebleFreq(nativeHandle, hz);
    }

    public void setTrebleQ(float q) {
        if (nativeHandle != 0) nativeSetTrebleQ(nativeHandle, q);
    }

    // Limiter instance methods
    public void setLimiterEnabled(boolean enabled) {
        if (nativeHandle != 0) nativeSetLimiterEnabled(nativeHandle, enabled);
    }

    public void setLimiterCeiling(float v) {
        if (nativeHandle != 0) nativeSetLimiterCeiling(nativeHandle, v);
    }

    public void setLimiterRelease(float ms) {
        if (nativeHandle != 0) nativeSetLimiterRelease(nativeHandle, ms);
    }

    public void setLimiterKnee(float dB) {
        if (nativeHandle != 0) nativeSetLimiterKnee(nativeHandle, dB);
    }

    // Stem mixer instance methods
    public void setStemModeActive(boolean active) {
        if (nativeHandle != 0) nativeSetStemModeActive(nativeHandle, active);
    }

    public boolean loadStems(String[] paths) {
        if (nativeHandle != 0) return nativeLoadStems(nativeHandle, paths);
        return false;
    }

    public void unloadStems() {
        if (nativeHandle != 0) nativeUnloadStems(nativeHandle);
    }

    public void setStemVolume(int stem, float vol) {
        if (nativeHandle != 0) nativeSetStemVolume(nativeHandle, stem, vol);
    }

    public void setStemMute(int stem, boolean muted) {
        if (nativeHandle != 0) nativeSetStemMute(nativeHandle, stem, muted);
    }

    public void setStemSolo(int stem, boolean soloed) {
        if (nativeHandle != 0) nativeSetStemSolo(nativeHandle, stem, soloed);
    }

    public void stemSeek(long samplePos) {
        if (nativeHandle != 0) nativeStemSeek(nativeHandle, samplePos);
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
        syncGlobalEq();
    }

    public static void broadcastPreampGain(float dB) {
        cachedPreampGain = dB;
        for (RoomEffectsProcessor p : playerInstances) p.setPreampGain(dB);
        syncGlobalEq();
    }

    public static void broadcastGraphicBandGain(int band, float dB) {
        if (band >= 0 && band < 32) cachedGraphicGains[band] = dB;
        for (RoomEffectsProcessor p : playerInstances) p.setGraphicBandGain(band, dB);
        syncGlobalEq();
    }

    public static void broadcastGraphicAllBands(float[] gains) {
        int count = Math.min(gains.length, 32);
        System.arraycopy(gains, 0, cachedGraphicGains, 0, count);
        for (RoomEffectsProcessor p : playerInstances) p.setGraphicAllBands(gains);
        syncGlobalEq();
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

    // ---- Package-private accessors for GlobalEqSessionManager ----

    static boolean isCachedEqEnabled() { return cachedEqEnabled; }
    static float[] getCachedGraphicGains() {
        float[] copy = new float[32];
        System.arraycopy(cachedGraphicGains, 0, copy, 0, 32);
        return copy;
    }
    static boolean isCachedToneEnabled() { return cachedToneEnabled; }
    static float getCachedBassGain() { return cachedBassGain; }
    static float getCachedBassFreq() { return cachedBassFreq; }
    static float getCachedTrebleGain() { return cachedTrebleGain; }
    static float getCachedTrebleFreq() { return cachedTrebleFreq; }
    static boolean isCachedLimiterEnabled() { return cachedLimiterEnabled; }
    static float getCachedLimiterCeiling() { return cachedLimiterCeiling; }
    static float getCachedLimiterRelease() { return cachedLimiterRelease; }

    /** Sync global EQ sessions when EQ-related params change. */
    private static void syncGlobalEq() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            GlobalEqSessionManager.syncAllSessions();
        }
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

    public static void broadcastMbcThreshold(float dB) {
        cachedMbcThreshold = dB;
        for (RoomEffectsProcessor p : playerInstances) p.setMbcThreshold(dB);
    }

    public static void broadcastMbcRatio(float ratio) {
        cachedMbcRatio = ratio;
        for (RoomEffectsProcessor p : playerInstances) p.setMbcRatio(ratio);
    }

    public static void broadcastMbcAttackTime(float ms) {
        cachedMbcAttackTime = ms;
        for (RoomEffectsProcessor p : playerInstances) p.setMbcAttackTime(ms);
    }

    public static void broadcastMbcReleaseTime(float ms) {
        cachedMbcReleaseTime = ms;
        for (RoomEffectsProcessor p : playerInstances) p.setMbcReleaseTime(ms);
    }

    public static void broadcastMbcPostGain(float dB) {
        cachedMbcPostGain = dB;
        for (RoomEffectsProcessor p : playerInstances) p.setMbcPostGain(dB);
    }

    // ---- Tone control broadcast methods ----

    public static void broadcastToneEnabled(boolean enabled) {
        cachedToneEnabled = enabled;
        for (RoomEffectsProcessor p : playerInstances) p.setToneEnabled(enabled);
        syncGlobalEq();
    }

    public static void broadcastBassGain(float dB) {
        cachedBassGain = dB;
        for (RoomEffectsProcessor p : playerInstances) p.setBassGain(dB);
        syncGlobalEq();
    }

    public static void broadcastBassFreq(float hz) {
        cachedBassFreq = hz;
        for (RoomEffectsProcessor p : playerInstances) p.setBassFreq(hz);
        syncGlobalEq();
    }

    public static void broadcastBassQ(float q) {
        cachedBassQ = q;
        for (RoomEffectsProcessor p : playerInstances) p.setBassQ(q);
    }

    public static void broadcastTrebleGain(float dB) {
        cachedTrebleGain = dB;
        for (RoomEffectsProcessor p : playerInstances) p.setTrebleGain(dB);
        syncGlobalEq();
    }

    public static void broadcastTrebleFreq(float hz) {
        cachedTrebleFreq = hz;
        for (RoomEffectsProcessor p : playerInstances) p.setTrebleFreq(hz);
        syncGlobalEq();
    }

    public static void broadcastTrebleQ(float q) {
        cachedTrebleQ = q;
        for (RoomEffectsProcessor p : playerInstances) p.setTrebleQ(q);
    }

    // ---- Speaker correction EQ instance methods ----

    public void setSpeakerEqEnabled(boolean enabled) {
        if (nativeHandle != 0) nativeSetSpeakerEqEnabled(nativeHandle, enabled);
    }

    public void setSpeakerEqBand(int band, float freq, float gainDb, float q,
                                  int filterType, boolean enabled) {
        if (nativeHandle != 0) nativeSetSpeakerEqBand(nativeHandle, band, freq, gainDb,
                q, filterType, enabled);
    }

    public void clearSpeakerEq() {
        if (nativeHandle != 0) nativeClearSpeakerEq(nativeHandle);
    }

    // ---- Speaker correction EQ broadcast methods ----

    public static void broadcastSpeakerEqEnabled(boolean enabled) {
        cachedSpeakerEqEnabled = enabled;
        for (RoomEffectsProcessor p : playerInstances) p.setSpeakerEqEnabled(enabled);
    }

    public static void broadcastSpeakerEqBands(float[] freqs, float[] gains,
                                                 float[] qs, int[] types, int count) {
        int n = Math.min(count, 32);
        cachedSpeakerBandCount = n;
        System.arraycopy(freqs, 0, cachedSpeakerEqFreqs, 0, n);
        System.arraycopy(gains, 0, cachedSpeakerEqGains, 0, n);
        System.arraycopy(qs, 0, cachedSpeakerEqQs, 0, n);
        System.arraycopy(types, 0, cachedSpeakerEqTypes, 0, n);
        for (RoomEffectsProcessor p : playerInstances) {
            for (int i = 0; i < n; i++) {
                p.setSpeakerEqBand(i, freqs[i], gains[i], qs[i], types[i], true);
            }
        }
    }

    public static void broadcastClearSpeakerEq() {
        cachedSpeakerBandCount = 0;
        for (int i = 0; i < 32; i++) {
            cachedSpeakerEqFreqs[i] = 0f;
            cachedSpeakerEqGains[i] = 0f;
            cachedSpeakerEqQs[i] = 0f;
            cachedSpeakerEqTypes[i] = 0;
        }
        for (RoomEffectsProcessor p : playerInstances) p.clearSpeakerEq();
    }

    // ---- Limiter broadcast methods ----

    public static void broadcastLimiterEnabled(boolean enabled) {
        cachedLimiterEnabled = enabled;
        for (RoomEffectsProcessor p : playerInstances) p.setLimiterEnabled(enabled);
        syncGlobalEq();
    }

    public static void broadcastLimiterCeiling(float v) {
        cachedLimiterCeiling = v;
        for (RoomEffectsProcessor p : playerInstances) p.setLimiterCeiling(v);
        syncGlobalEq();
    }

    public static void broadcastLimiterRelease(float ms) {
        cachedLimiterRelease = ms;
        for (RoomEffectsProcessor p : playerInstances) p.setLimiterRelease(ms);
        syncGlobalEq();
    }

    public static void broadcastLimiterKnee(float dB) {
        cachedLimiterKnee = dB;
        for (RoomEffectsProcessor p : playerInstances) p.setLimiterKnee(dB);
    }

    // ---- Stem mixer broadcast methods ----

    public static void broadcastStemModeActive(boolean active) {
        cachedStemModeActive = active;
        for (RoomEffectsProcessor p : playerInstances) p.setStemModeActive(active);
    }

    public static void broadcastLoadStems(String[] paths) {
        cachedStemPaths = paths.clone();
        for (RoomEffectsProcessor p : playerInstances) p.loadStems(paths);
    }

    public static void broadcastUnloadStems() {
        cachedStemPaths = null;
        cachedStemModeActive = false;
        for (RoomEffectsProcessor p : playerInstances) {
            p.unloadStems();
            p.setStemModeActive(false);
        }
    }

    public static void broadcastStemVolume(int stem, float vol) {
        if (stem >= 0 && stem < 4) cachedStemVolumes[stem] = vol;
        for (RoomEffectsProcessor p : playerInstances) p.setStemVolume(stem, vol);
    }

    public static void broadcastStemMute(int stem, boolean muted) {
        if (stem >= 0 && stem < 4) cachedStemMutes[stem] = muted;
        for (RoomEffectsProcessor p : playerInstances) p.setStemMute(stem, muted);
    }

    public static void broadcastStemSolo(int stem, boolean soloed) {
        if (stem >= 0 && stem < 4) cachedStemSolos[stem] = soloed;
        for (RoomEffectsProcessor p : playerInstances) p.setStemSolo(stem, soloed);
    }

    public static void broadcastStemSeek(long samplePos) {
        for (RoomEffectsProcessor p : playerInstances) p.stemSeek(samplePos);
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
    private native void nativeSetMbcThreshold(long handle, float dB);
    private native void nativeSetMbcRatio(long handle, float ratio);
    private native void nativeSetMbcAttackTime(long handle, float ms);
    private native void nativeSetMbcReleaseTime(long handle, float ms);
    private native void nativeSetMbcPostGain(long handle, float dB);

    // Tone control natives
    private native void nativeSetToneEnabled(long handle, boolean enabled);
    private native void nativeSetBassGain(long handle, float dB);
    private native void nativeSetBassFreq(long handle, float hz);
    private native void nativeSetBassQ(long handle, float q);
    private native void nativeSetTrebleGain(long handle, float dB);
    private native void nativeSetTrebleFreq(long handle, float hz);
    private native void nativeSetTrebleQ(long handle, float q);

    // Limiter natives
    private native void nativeSetLimiterEnabled(long handle, boolean enabled);
    private native void nativeSetLimiterCeiling(long handle, float v);
    private native void nativeSetLimiterRelease(long handle, float ms);
    private native void nativeSetLimiterKnee(long handle, float dB);

    // Speaker correction EQ natives
    private native void nativeSetSpeakerEqEnabled(long handle, boolean enabled);
    private native void nativeSetSpeakerEqBand(long handle, int band, float freq,
                                                float gainDb, float q, int filterType,
                                                boolean enabled);
    private native void nativeClearSpeakerEq(long handle);

    // Stem mixer natives
    private native boolean nativeLoadStems(long handle, String[] paths);
    private native void nativeUnloadStems(long handle);
    private native void nativeSetStemModeActive(long handle, boolean active);
    private native void nativeSetStemVolume(long handle, int stem, float vol);
    private native void nativeSetStemMute(long handle, int stem, boolean muted);
    private native void nativeSetStemSolo(long handle, int stem, boolean soloed);
    private native void nativeStemSeek(long handle, long samplePos);
    private native boolean nativeAreStemsLoaded(long handle);
    private native long nativeGetStemPosition(long handle);
    private native long nativeGetStemTotalFrames(long handle);
}
