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
    private static DynamicsProcessing.Limiter dspLimiter;

    public static final int GRAPHIC_BAND_COUNT = 32;
    public static final int PARAMETRIC_BAND_COUNT = 32;
    public static final int MBC_BAND_COUNT = 10;

    public static final int priority = Integer.MAX_VALUE;

    // Default DSP values
    private static final float DEFAULT_OUT_GAIN = 2.0f;
    private static final float DEFAULT_INPUT_GAIN = -4.0f;
    private static final float DEFAULT_POWER_BASS = 2.0f;
    private static final float DEFAULT_X_BASS = 3.0f;
    private static final float DEFAULT_X_BASS2 = 4.0f;
    private static final float DEFAULT_TREBLE = 3.3f;

    static int audioSessionId = 0;

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

    // Engine config: 32-band Pre-EQ, 10-band MBC, 32-band Post-EQ, limiter
    private static DynamicsProcessing.Config buildConfig() {
        DynamicsProcessing.Config.Builder builder = new DynamicsProcessing.Config.Builder(
            0,                      // variant
            2,                      // channel count (stereo)
            true,                   // pre-EQ enabled
            GRAPHIC_BAND_COUNT,     // pre-EQ band count (32)
            true,                   // MBC enabled
            MBC_BAND_COUNT,         // MBC band count (10)
            true,                   // post-EQ enabled
            PARAMETRIC_BAND_COUNT,  // post-EQ band count (32)
            true                    // limiter enabled
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
        if (dspEngine != null) return;

        try {
            DynamicsProcessing.Config config = buildConfig();
            int sessionId = audioSessionId > 0 ? audioSessionId : 0;
            dspEngine = new DynamicsProcessing(priority, sessionId, config);

            // Create separate Pre-EQ (graphic) and Post-EQ (parametric)
            preEq = new DynamicsProcessing.Eq(true, true, GRAPHIC_BAND_COUNT);
            postEq = new DynamicsProcessing.Eq(true, true, PARAMETRIC_BAND_COUNT);

            // MBC
            dspMbc = new DynamicsProcessing.Mbc(true, true, MBC_BAND_COUNT);

            // Limiter
            dspLimiter = new DynamicsProcessing.Limiter(
                true,               // enabled
                true,               // in linear domain
                10,                 // link channels
                1.0f,               // attack time (ms)
                30.0f,              // release time (ms)
                6.0f,               // ratio
                -1.0f,              // threshold (dB)
                DEFAULT_OUT_GAIN    // output gain
            );

            // Configure Pre-EQ with ISO frequencies
            for (int b = 0; b < GRAPHIC_BAND_COUNT; b++) {
                preEq.getBand(b).setCutoffFrequency(GRAPHIC_FREQUENCIES[b]);
                preEq.getBand(b).setGain(0.0f);
            }

            // Configure Post-EQ with same ISO frequencies (user can change freq via parametric)
            for (int b = 0; b < PARAMETRIC_BAND_COUNT; b++) {
                postEq.getBand(b).setCutoffFrequency(GRAPHIC_FREQUENCIES[b]);
                postEq.getBand(b).setGain(0.0f);
            }

            // Configure MBC bands
            initMbcDefaults();

            // Apply to engine
            dspEngine.setInputGainAllChannelsTo(DEFAULT_INPUT_GAIN);
            dspEngine.setPreEqAllChannelsTo(preEq);
            dspEngine.setPostEqAllChannelsTo(postEq);
            dspEngine.setMbcAllChannelsTo(dspMbc);
            dspEngine.setLimiterAllChannelsTo(dspLimiter);

            Log.d(TAG, "DSPEngine initialized with 32+32 bands, session=" + sessionId);
        } catch (Exception e) {
            Log.e(TAG, "Failed to initialize DSPEngine", e);
            dspEngine = null;
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
            band.setPreGain(3.0f);
            band.setPostGain(2.0f);
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

    // ======================== ENGINE CONTROL ========================

    public static void enableEngine(boolean enable) {
        if (dspEngine == null) return;
        try {
            dspEngine.setEnabled(enable);
            if (preEq != null) preEq.setEnabled(enable);
            if (postEq != null) postEq.setEnabled(enable);
            if (dspMbc != null) dspMbc.setEnabled(enable);
            if (dspLimiter != null) dspLimiter.setEnabled(enable);
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
            dspLimiter = null;
        }
    }

    // ======================== LIMITER ========================

    public static void setOutGain(float gain) {
        if (dspEngine == null || dspLimiter == null) return;
        try {
            dspLimiter.setPostGain(gain);
            dspEngine.setLimiterAllChannelsTo(dspLimiter);
        } catch (Exception e) {
            Log.e(TAG, "setOutGain error", e);
        }
    }

    public static float getGainValue() {
        if (dspLimiter != null) return dspLimiter.getPostGain();
        return 0.0f;
    }

    public static void setAudioThreshold(float threshold) {
        if (dspEngine == null || dspLimiter == null) return;
        dspLimiter.setThreshold(threshold);
        dspEngine.setLimiterAllChannelsTo(dspLimiter);
    }

    public static void setRelease(float release) {
        if (dspEngine == null || dspLimiter == null) return;
        dspLimiter.setReleaseTime(release);
        dspEngine.setLimiterAllChannelsTo(dspLimiter);
    }

    public static void setAttackTime(float attack) {
        if (dspEngine == null || dspLimiter == null) return;
        dspLimiter.setAttackTime(attack);
        dspEngine.setLimiterAllChannelsTo(dspLimiter);
    }

    public static void setAudioRatio(float ratio) {
        if (dspEngine == null || dspLimiter == null) return;
        dspLimiter.setRatio(ratio);
        dspEngine.setLimiterAllChannelsTo(dspLimiter);
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
        if (dspEngine == null) return;
        dspEngine.setInputGainAllChannelsTo(volume);
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
