package x.a.zix;

import android.media.audiofx.DynamicsProcessing;
import android.os.Build;
import android.util.Log;

import androidx.annotation.RequiresApi;

@RequiresApi(api = Build.VERSION_CODES.P)
public class DSPEngine {
    private static final String TAG = "DSPEngine";

    private static DynamicsProcessing dspEngine;
    private static DynamicsProcessing.Eq preEq;   // Graphic EQ (32 bands)
    private static DynamicsProcessing.Eq postEq;   // Parametric EQ (32 bands)
    private static DynamicsProcessing.Mbc dspMbc;

    public static final int GRAPHIC_BAND_COUNT = 32;
    public static final int PARAMETRIC_BAND_COUNT = 32;
    public static final int MBC_BAND_COUNT = 10;

    public static final int priority = Integer.MAX_VALUE;

    // Default DSP values
    private static final float DEFAULT_OUT_GAIN = 0.0f;
    private static final float DEFAULT_INPUT_GAIN = 0.0f;
    private static final float DEFAULT_POWER_BASS = 2.0f;
    private static final float DEFAULT_X_BASS = 3.0f;
    private static final float DEFAULT_X_BASS2 = 4.0f;
    private static final float DEFAULT_TREBLE = 3.3f;

    static int audioSessionId = 0;
    private static int boundSessionId = -1; // session ID the engine was created with
    private static float preampGain = 0.0f; // preamp boost in dB (0-15)
    private static boolean mbcEnabled = false; // user toggle for MBC compressor

    // 32-band ISO 1/3 octave center frequencies (Hz)
    public static final int[] GRAPHIC_FREQUENCIES = {
        20, 25, 31, 40, 50, 63, 80, 100,
        125, 160, 200, 250, 315, 400, 500, 630,
        800, 1000, 1250, 1600, 2000, 2500, 3150, 4000,
        5000, 6300, 8000, 10000, 12500, 16000, 18000, 20000
    };

    // Default flat gains for graphic EQ
    private static final float[] DEFAULT_GRAPHIC_GAINS = new float[GRAPHIC_BAND_COUNT]; // all 0.0f

    // MBC frequencies (10 bands covering key ranges)
    private static final int[] MBC_FREQUENCIES = {
        31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
    };

    // Legacy DSP speakers config (for backwards compatibility)
    static int[] dsp_speakers = {31, 62, 85, 250, 500, 1000, 2000, 4000, 8000, 16000};
    static float[] dsp_gains = {4.8f, 3.6f, 3.0f, 5.0f, 5f, 3f, 5f, 6f, 4f, 7f};

    // Engine config: 32-band Pre-EQ, 10-band MBC, 32-band Post-EQ, no limiter
    private static DynamicsProcessing.Config buildConfig() {
        DynamicsProcessing.Config.Builder builder = new DynamicsProcessing.Config.Builder(
            0,                      // variant
            2,                      // channel count (stereo)
            true,                   // pre-EQ enabled
            GRAPHIC_BAND_COUNT,     // pre-EQ band count (32)
            false,                  // MBC disabled by default (user toggle)
            MBC_BAND_COUNT,         // MBC band count (10)
            true,                   // post-EQ enabled
            PARAMETRIC_BAND_COUNT,  // post-EQ band count (32)
            false                   // limiter disabled — auto-gain compensation instead
        );
        builder.setPreferredFrameDuration(20.0f);
        return builder.build();
    }

    public static boolean isDynamicsProcessingAvailable() {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.P;
    }

    public static void setAudioSessionId(int id) {
        audioSessionId = id;
    }

    // ======================== INITIALIZATION ========================

    public static void initDSPEngine() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return;

        int sessionId = audioSessionId > 0 ? audioSessionId : 0;

        // If already initialized with the same session, nothing to do
        if (dspEngine != null && boundSessionId == sessionId) return;

        // Session changed — snapshot current gains, dispose, and recreate
        float[] savedGraphicGains = null;
        float[] savedParametricFreqs = null;
        float[] savedParametricGains = null;
        boolean wasEnabled = false;

        if (dspEngine != null) {
            wasEnabled = dspEngine.getEnabled();
            // Save current graphic EQ gains
            if (preEq != null) {
                savedGraphicGains = new float[GRAPHIC_BAND_COUNT];
                for (int i = 0; i < GRAPHIC_BAND_COUNT; i++) {
                    savedGraphicGains[i] = preEq.getBand(i).getGain();
                }
            }
            // Save current parametric EQ
            if (postEq != null) {
                savedParametricFreqs = new float[PARAMETRIC_BAND_COUNT];
                savedParametricGains = new float[PARAMETRIC_BAND_COUNT];
                for (int i = 0; i < PARAMETRIC_BAND_COUNT; i++) {
                    savedParametricFreqs[i] = postEq.getBand(i).getCutoffFrequency();
                    savedParametricGains[i] = postEq.getBand(i).getGain();
                }
            }
            Log.d(TAG, "Session changed " + boundSessionId + " -> " + sessionId + ", reinitializing");
            dispose();
        }

        try {
            DynamicsProcessing.Config config = buildConfig();
            dspEngine = new DynamicsProcessing(priority, sessionId, config);
            boundSessionId = sessionId;

            // Create separate Pre-EQ (graphic) and Post-EQ (parametric)
            preEq = new DynamicsProcessing.Eq(true, true, GRAPHIC_BAND_COUNT);
            postEq = new DynamicsProcessing.Eq(true, true, PARAMETRIC_BAND_COUNT);

            // MBC
            dspMbc = new DynamicsProcessing.Mbc(true, true, MBC_BAND_COUNT);

            // Configure Pre-EQ with ISO frequencies and restore gains
            for (int b = 0; b < GRAPHIC_BAND_COUNT; b++) {
                preEq.getBand(b).setCutoffFrequency(GRAPHIC_FREQUENCIES[b]);
                preEq.getBand(b).setGain(savedGraphicGains != null ? savedGraphicGains[b] : 0.0f);
            }

            // Configure Post-EQ — restore parametric settings if available
            for (int b = 0; b < PARAMETRIC_BAND_COUNT; b++) {
                float freq = savedParametricFreqs != null ? savedParametricFreqs[b] : GRAPHIC_FREQUENCIES[b];
                float gain = savedParametricGains != null ? savedParametricGains[b] : 0.0f;
                postEq.getBand(b).setCutoffFrequency(freq);
                postEq.getBand(b).setGain(gain);
            }

            // Configure MBC bands
            initMbcDefaults();

            // Apply to engine
            dspEngine.setPreEqAllChannelsTo(preEq);
            dspEngine.setPostEqAllChannelsTo(postEq);
            dspMbc.setEnabled(mbcEnabled);
            dspEngine.setMbcAllChannelsTo(dspMbc);
            recomputeInputGain();

            // Restore enabled state
            if (wasEnabled) {
                dspEngine.setEnabled(true);
            }

            Log.d(TAG, "DSPEngine initialized with 32+32 bands, session=" + sessionId);
        } catch (Exception e) {
            Log.e(TAG, "Failed to initialize DSPEngine", e);
            dspEngine = null;
            boundSessionId = -1;
        }
    }

    private static void initMbcDefaults() {
        for (int i = 0; i < MBC_BAND_COUNT; i++) {
            DynamicsProcessing.MbcBand band = dspMbc.getBand(i);
            band.setCutoffFrequency(MBC_FREQUENCIES[i]);
            band.setAttackTime(15.0f);
            band.setReleaseTime(45.0f);
            band.setRatio(2.5f);
            band.setKneeWidth(8.0f);
            band.setThreshold(-18.0f);
            band.setNoiseGateThreshold(-70.0f);
            band.setExpanderRatio(2.0f);
            band.setPreGain(0.0f);
            band.setPostGain(0.0f);
            band.setEnabled(true);
        }
    }

    // ======================== GRAPHIC EQ (Pre-EQ, 32 bands) ========================

    public static void setGraphicBandGain(int band, float gain) {
        if (dspEngine == null || preEq == null) return;
        if (band < 0 || band >= GRAPHIC_BAND_COUNT) return;
        try {
            preEq.getBand(band).setGain(gain);
            dspEngine.setPreEqBandAllChannelsTo(band, preEq.getBand(band));
            recomputeInputGain();
        } catch (Exception e) {
            Log.e(TAG, "setGraphicBandGain error band=" + band, e);
        }
    }

    public static float getGraphicBandGain(int band) {
        if (preEq == null || band < 0 || band >= GRAPHIC_BAND_COUNT) return 0.0f;
        return preEq.getBand(band).getGain();
    }

    public static void setGraphicAllBands(float[] gains) {
        if (dspEngine == null || preEq == null) return;
        int count = Math.min(gains.length, GRAPHIC_BAND_COUNT);
        for (int i = 0; i < count; i++) {
            preEq.getBand(i).setGain(gains[i]);
        }
        dspEngine.setPreEqAllChannelsTo(preEq);
        recomputeInputGain();
    }

    public static float[] getGraphicAllBands() {
        float[] gains = new float[GRAPHIC_BAND_COUNT];
        if (preEq == null) return gains;
        for (int i = 0; i < GRAPHIC_BAND_COUNT; i++) {
            gains[i] = preEq.getBand(i).getGain();
        }
        return gains;
    }

    // ======================== PARAMETRIC EQ (Post-EQ, 32 bands) ========================

    public static void setParametricBand(int band, float freq, float gain) {
        if (dspEngine == null || postEq == null) return;
        if (band < 0 || band >= PARAMETRIC_BAND_COUNT) return;
        try {
            postEq.getBand(band).setCutoffFrequency(freq);
            postEq.getBand(band).setGain(gain);
            dspEngine.setPostEqBandAllChannelsTo(band, postEq.getBand(band));
            recomputeInputGain();
        } catch (Exception e) {
            Log.e(TAG, "setParametricBand error band=" + band, e);
        }
    }

    public static float[] getParametricBand(int band) {
        if (postEq == null || band < 0 || band >= PARAMETRIC_BAND_COUNT) {
            return new float[]{0.0f, 0.0f};
        }
        return new float[]{
            postEq.getBand(band).getCutoffFrequency(),
            postEq.getBand(band).getGain()
        };
    }

    public static void setParametricAllBands(float[] freqs, float[] gains) {
        if (dspEngine == null || postEq == null) return;
        int count = Math.min(Math.min(freqs.length, gains.length), PARAMETRIC_BAND_COUNT);
        for (int i = 0; i < count; i++) {
            postEq.getBand(i).setCutoffFrequency(freqs[i]);
            postEq.getBand(i).setGain(gains[i]);
        }
        dspEngine.setPostEqAllChannelsTo(postEq);
        recomputeInputGain();
    }

    // ======================== LEGACY DSP METHODS (backwards compat) ========================

    public static void setDspSpeakers(int[] speakers, float[] gains) {
        dsp_speakers = speakers;
        dsp_gains = gains;
        // Apply to MBC cutoff frequencies (first 10 bands)
        if (dspEngine != null && dspMbc != null) {
            int count = Math.min(speakers.length, MBC_BAND_COUNT);
            for (int b = 0; b < count; b++) {
                try {
                    dspMbc.getBand(b).setCutoffFrequency(speakers[b]);
                } catch (Exception e) {
                    Log.e(TAG, "setDspSpeakers error band=" + b, e);
                }
            }
            dspEngine.setMbcAllChannelsTo(dspMbc);
        }
    }

    // Legacy band config — maps old 10-band indices to graphic EQ
    private static void legacyBandConfig(int band, float gain) {
        if (dspEngine == null || preEq == null) return;
        // Map legacy 10-band index to nearest graphic EQ band
        int mappedBand = mapLegacyToGraphicBand(band);
        if (mappedBand >= 0 && mappedBand < GRAPHIC_BAND_COUNT) {
            setGraphicBandGain(mappedBand, gain);
        }
    }

    private static int mapLegacyToGraphicBand(int legacyBand) {
        // Legacy frequencies: {31, 62, 85, 250, 500, 1000, 2000, 4000, 8000, 16000}
        // Map to closest graphic EQ band index
        int[] mapping = {2, 5, 6, 9, 14, 17, 20, 23, 26, 29};
        if (legacyBand >= 0 && legacyBand < mapping.length) {
            return mapping[legacyBand];
        }
        return -1;
    }

    public static float getVocalLevel() {
        if (preEq != null) {
            // Band 14 = 500Hz (vocal range)
            return preEq.getBand(14).getGain();
        }
        return 0;
    }

    // ======================== PREAMP ========================

    public static void setPreamp(float dB) {
        preampGain = Math.max(0.0f, Math.min(15.0f, dB));
        recomputeInputGain();
    }

    public static float getPreamp() {
        return preampGain;
    }

    // ======================== MBC TOGGLE ========================

    public static void enableMbc(boolean enable) {
        mbcEnabled = enable;
        if (dspEngine == null || dspMbc == null) return;
        try {
            dspMbc.setEnabled(enable);
            dspEngine.setMbcAllChannelsTo(dspMbc);
        } catch (Exception e) {
            Log.e(TAG, "enableMbc error", e);
        }
    }

    public static boolean isMbcEnabled() {
        return mbcEnabled;
    }

    // ======================== ENGINE CONTROL ========================

    public static void enableEngine(boolean enable) {
        if (dspEngine == null) return;
        try {
            dspEngine.setEnabled(enable);
            if (preEq != null) preEq.setEnabled(enable);
            if (postEq != null) postEq.setEnabled(enable);
            if (dspMbc != null) dspMbc.setEnabled(mbcEnabled && enable);
        } catch (Exception e) {
            Log.e(TAG, "enableEngine error", e);
        }
    }

    public static void dispose() {
        if (dspEngine != null) {
            try {
                dspEngine.setEnabled(false);
                dspEngine.release();
            } catch (Exception e) {
                Log.e(TAG, "dispose error", e);
            }
            dspEngine = null;
            preEq = null;
            postEq = null;
            dspMbc = null;
            boundSessionId = -1;
        }
    }

    // ======================== AUTO-GAIN COMPENSATION ========================
    // Instead of a limiter, we reduce input gain by the peak EQ boost so the
    // signal never clips.  preamp is added on top, so effective input gain =
    // preampGain - peakBoost.

    private static void recomputeInputGain() {
        if (dspEngine == null) return;
        float peakBoost = 0.0f;
        if (preEq != null) {
            for (int i = 0; i < GRAPHIC_BAND_COUNT; i++) {
                float g = preEq.getBand(i).getGain();
                if (g > peakBoost) peakBoost = g;
            }
        }
        if (postEq != null) {
            for (int i = 0; i < PARAMETRIC_BAND_COUNT; i++) {
                float g = postEq.getBand(i).getGain();
                if (g > peakBoost) peakBoost = g;
            }
        }
        // effective = preamp - peakBoost (never less than -15 dB)
        float effective = preampGain - peakBoost;
        effective = Math.max(-15.0f, effective);
        try {
            dspEngine.setInputGainAllChannelsTo(effective);
        } catch (Exception e) {
            Log.e(TAG, "recomputeInputGain error", e);
        }
    }

    // ======================== MBC / COMPRESSOR ========================

    public static void setNoiseThreshold(float noiseThreshold) {
        if (dspEngine == null || dspMbc == null) return;
        for (int i = 0; i < MBC_BAND_COUNT; i++) {
            dspMbc.getBand(i).setNoiseGateThreshold(noiseThreshold);
        }
        dspEngine.setMbcAllChannelsTo(dspMbc);
    }

    public static void setKneeWidth(float knee) {
        if (dspEngine == null || dspMbc == null) return;
        for (int i = 0; i < MBC_BAND_COUNT; i++) {
            dspMbc.getBand(i).setKneeWidth(knee);
        }
        dspEngine.setMbcAllChannelsTo(dspMbc);
    }

    public static void setPreGain(float gain) {
        if (dspEngine == null || dspMbc == null) return;
        for (int i = 0; i < MBC_BAND_COUNT; i++) {
            dspMbc.getBand(i).setPreGain(gain);
        }
        dspEngine.setMbcAllChannelsTo(dspMbc);
    }

    public static void setExpanderRatio(float ratio) {
        if (dspEngine == null || dspMbc == null) return;
        for (int i = 0; i < MBC_BAND_COUNT; i++) {
            dspMbc.getBand(i).setExpanderRatio(ratio);
        }
        dspEngine.setMbcAllChannelsTo(dspMbc);
    }

    // ======================== DSP POWER SETTINGS (legacy) ========================

    public static void setDSPPowerBass(float gain) {
        if (dspEngine == null) return;
        legacyBandConfig(1, gain);
    }

    public static void setDSPXBass(float gain) {
        if (dspEngine == null) return;
        legacyBandConfig(0, gain);
    }

    public static void setDSPx(float gain) {
        if (dspEngine == null) return;
        legacyBandConfig(2, gain);
    }

    public static void setDSPVolume(float volume) {
        // Legacy path — also updates preamp state
        setPreamp(volume);
    }

    public static void setDSPTreble(float gain) {
        if (dspEngine == null) return;
        legacyBandConfig(9, gain);
    }

    public static void adjustTunerVocal(float gain) {
        if (preEq == null) return;
        // Vocal range ~ 500Hz = band index 14
        setGraphicBandGain(14, gain);
    }

    // Legacy tuner stubs (tuner removed — was never initialized)
    public static void setCutOffFrequencyForTunerBass(int frequency) {
        // No-op: tuner removed
    }

    public static void setFrequencyForBassTuner(float bass) {
        // No-op: tuner removed
    }

    public static void setFrequencyTrebleForTuner(float treble) {
        // No-op: tuner removed
    }

    public static void setBassTone(float bass) {
        // No-op: tuner removed
    }
}
