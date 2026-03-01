package x.a.zix;

import android.media.audiofx.DynamicsProcessing;
import android.os.Build;
import android.util.Log;

import androidx.annotation.RequiresApi;

import java.util.concurrent.ConcurrentHashMap;

/**
 * Manages DynamicsProcessing instances attached to external apps' audio sessions.
 * Each external session gets its own DynamicsProcessing configured from RoomEffectsProcessor's
 * cached EQ/tone/limiter state.
 *
 * The in-app C++ DSP pipeline is completely independent — this only affects external audio.
 */
@RequiresApi(api = Build.VERSION_CODES.P)
public class GlobalEqSessionManager {
    private static final String TAG = "GlobalEqSessionManager";

    // ISO 1/3-octave center frequencies for 32-band graphic EQ
    private static final float[] ISO_FREQS = {
        20f, 25f, 31.5f, 40f, 50f, 63f, 80f, 100f,
        125f, 160f, 200f, 250f, 315f, 400f, 500f, 630f,
        800f, 1000f, 1250f, 1600f, 2000f, 2500f, 3150f, 4000f,
        5000f, 6300f, 8000f, 10000f, 12500f, 16000f, 18000f, 20000f
    };

    private static final ConcurrentHashMap<Integer, DynamicsProcessing> sessions =
            new ConcurrentHashMap<>();
    private static volatile boolean enabled = false;

    private GlobalEqSessionManager() {}

    public static boolean isEnabled() {
        return enabled;
    }

    public static void setEnabled(boolean on) {
        enabled = on;
        if (!on) {
            releaseAll();
        }
    }

    /**
     * Attach a DynamicsProcessing to an external app's audio session.
     * Configures 32-band Pre-EQ + Limiter from RoomEffectsProcessor's cached state.
     */
    public static void attachSession(int sessionId, String pkg) {
        if (!enabled) return;
        if (sessions.containsKey(sessionId)) return;

        try {
            DynamicsProcessing dp = createConfiguredInstance(sessionId);
            dp.setEnabled(true);
            sessions.put(sessionId, dp);
            Log.i(TAG, "Attached session " + sessionId + " (" + pkg + "), total: " + sessions.size());
        } catch (Exception e) {
            Log.e(TAG, "Failed to attach session " + sessionId + ": " + e.getMessage());
        }
    }

    /** Detach and release a session's DynamicsProcessing. */
    public static void detachSession(int sessionId) {
        DynamicsProcessing dp = sessions.remove(sessionId);
        if (dp != null) {
            try {
                dp.setEnabled(false);
                dp.release();
            } catch (Exception e) {
                Log.w(TAG, "Error releasing session " + sessionId, e);
            }
            Log.i(TAG, "Detached session " + sessionId + ", remaining: " + sessions.size());
        }
    }

    /** Release all sessions (called when service stops). */
    public static void releaseAll() {
        for (Integer id : sessions.keySet()) {
            DynamicsProcessing dp = sessions.remove(id);
            if (dp != null) {
                try {
                    dp.setEnabled(false);
                    dp.release();
                } catch (Exception ignored) {}
            }
        }
        Log.i(TAG, "Released all sessions");
    }

    /**
     * Re-apply current EQ state to all active sessions.
     * Called whenever the user changes EQ/tone/limiter settings.
     */
    public static void syncAllSessions() {
        if (!enabled || sessions.isEmpty()) return;

        for (DynamicsProcessing dp : sessions.values()) {
            try {
                applyState(dp);
            } catch (Exception e) {
                Log.w(TAG, "Error syncing session: " + e.getMessage());
            }
        }
    }

    /** Create a DynamicsProcessing instance configured from cached state. */
    private static DynamicsProcessing createConfiguredInstance(int sessionId) {
        // Build config: Pre-EQ with 32 bands, no MBC, no Post-EQ, limiter enabled
        DynamicsProcessing.Config.Builder builder = new DynamicsProcessing.Config.Builder(
                DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                /* channelCount */ 2,
                /* preEqInUse */ true,
                /* preEqBandCount */ 32,
                /* mbcInUse */ false,
                /* mbcBandCount */ 0,
                /* postEqInUse */ false,
                /* postEqBandCount */ 0,
                /* limiterInUse */ true
        );

        // Priority: higher = takes precedence over other audio effects on this session.
        // Use max priority so Hype EQ overrides system/OEM equalizers.
        DynamicsProcessing dp = new DynamicsProcessing(Integer.MAX_VALUE, sessionId, builder.build());
        applyState(dp);
        return dp;
    }

    /** Apply all EQ/tone/limiter state from RoomEffectsProcessor's cache to a DynamicsProcessing. */
    private static void applyState(DynamicsProcessing dp) {
        boolean eqEnabled = RoomEffectsProcessor.isCachedEqEnabled();
        float preamp = RoomEffectsProcessor.getCachedPreampGain();
        float[] graphicGains = RoomEffectsProcessor.getCachedGraphicGains();
        boolean toneEnabled = RoomEffectsProcessor.isCachedToneEnabled();
        float bassGain = RoomEffectsProcessor.getCachedBassGain();
        float bassFreq = RoomEffectsProcessor.getCachedBassFreq();
        float trebleGain = RoomEffectsProcessor.getCachedTrebleGain();
        float trebleFreq = RoomEffectsProcessor.getCachedTrebleFreq();
        boolean limiterEnabled = RoomEffectsProcessor.isCachedLimiterEnabled();
        float limiterCeiling = RoomEffectsProcessor.getCachedLimiterCeiling();
        float limiterRelease = RoomEffectsProcessor.getCachedLimiterRelease();

        // Input gain = preamp
        dp.setInputGainAllChannelsTo(eqEnabled ? preamp : 0f);

        // Pre-EQ bands
        for (int ch = 0; ch < 2; ch++) {
            DynamicsProcessing.Eq preEq = dp.getPreEqByChannelIndex(ch);
            preEq.setEnabled(eqEnabled);

            for (int i = 0; i < 32; i++) {
                DynamicsProcessing.EqBand band = preEq.getBand(i);
                band.setCutoffFrequency(ISO_FREQS[i]);

                float gain = eqEnabled ? graphicGains[i] : 0f;

                // Apply tone shelves on top of graphic EQ
                if (eqEnabled && toneEnabled) {
                    if (ISO_FREQS[i] <= bassFreq) {
                        gain += bassGain;
                    }
                    if (ISO_FREQS[i] >= trebleFreq) {
                        gain += trebleGain;
                    }
                }

                band.setGain(gain);
                preEq.setBand(i, band);
            }

            dp.setPreEqByChannelIndex(ch, preEq);
        }

        // Limiter
        for (int ch = 0; ch < 2; ch++) {
            DynamicsProcessing.Limiter limiter = dp.getLimiterByChannelIndex(ch);
            limiter.setEnabled(limiterEnabled);
            // DynamicsProcessing limiter threshold is in dBFS
            // Our ceiling is 0.0-1.0 linear, convert: 20*log10(ceiling)
            float thresholdDb = (float) (20.0 * Math.log10(Math.max(limiterCeiling, 0.01)));
            limiter.setThreshold(thresholdDb);
            limiter.setPostGain(0f);
            // Attack: instant for limiting
            limiter.setAttackTime(0.1f);
            limiter.setReleaseTime(limiterRelease);
            // Ratio: hard limiting
            limiter.setRatio(20f);
            dp.setLimiterByChannelIndex(ch, limiter);
        }
    }
}
