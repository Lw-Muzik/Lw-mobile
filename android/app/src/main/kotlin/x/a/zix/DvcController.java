package x.a.zix;

import android.content.Context;
import android.database.ContentObserver;
import android.media.AudioManager;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;

import io.flutter.plugin.common.EventChannel;

/**
 * Direct Volume Control — Poweramp-style.
 *
 * When enabled, system STREAM_MUSIC volume is forced to max so the full
 * digital range reaches the DAC.  Internal volume is then controlled via
 * {@link LoudnessControl} (LoudnessEnhancer) which sits after the DSP chain.
 *
 * At very low gain levels (&lt; SYSTEM_VOL_THRESHOLD dB) we start reducing the
 * actual system volume to reach true silence, since LoudnessEnhancer cannot
 * attenuate below unity on most devices.
 *
 * A {@link ContentObserver} watches for external volume changes and re-forces
 * the correct level, forwarding the event to Flutter so the DVC gain slider
 * can respond instead.
 */
public class DvcController {

    private static AudioManager audioManager;
    private static int savedSystemVolume = -1;
    private static boolean dvcActive = false;
    private static ContentObserver volumeObserver;
    private static Handler handler;
    private static boolean suppressObserver = false;

    // Below this gain (dB) we start scaling system volume down toward 0.
    // Above it, system stays at max and LoudnessEnhancer handles the gain.
    private static final float SYSTEM_VOL_THRESHOLD = -20.0f; // dB
    private static final float MUTE_THRESHOLD = -30.0f;       // dB — silence

    // Track current gain so the observer knows whether to re-force max
    private static float currentGainDb = 0.0f;

    // EventChannel sink for forwarding volume-button events to Flutter
    private static EventChannel.EventSink eventSink;

    public static void init(Context context) {
        audioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
        handler = new Handler(Looper.getMainLooper());
    }

    /**
     * Set up the EventChannel that sends "up"/"down" events to Dart when
     * hardware volume buttons are pressed while DVC is active.
     */
    public static void setupEventChannel(EventChannel channel) {
        channel.setStreamHandler(new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object arguments, EventChannel.EventSink sink) {
                eventSink = sink;
            }

            @Override
            public void onCancel(Object arguments) {
                eventSink = null;
            }
        });
    }

    /**
     * Enable DVC: save current system volume, set STREAM_MUSIC to max,
     * enable LoudnessEnhancer, and register the volume observer.
     */
    public static void enable(Context context) {
        if (audioManager == null) init(context);
        if (dvcActive) return;

        savedSystemVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC);
        int maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC);

        suppressObserver = true;
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, maxVol, 0);
        suppressObserver = false;

        LoudnessControl.enable(true);
        dvcActive = true;

        registerVolumeObserver(context);
    }

    /**
     * Disable DVC: unregister observer, restore saved system volume,
     * disable LoudnessEnhancer.
     */
    public static void disable(Context context) {
        if (!dvcActive) return;

        unregisterVolumeObserver(context);

        if (savedSystemVolume >= 0 && audioManager != null) {
            suppressObserver = true;
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, savedSystemVolume, 0);
            suppressObserver = false;
        }

        LoudnessControl.enable(false);
        dvcActive = false;
        savedSystemVolume = -1;
    }

    /**
     * Apply DVC gain in dB.  Above SYSTEM_VOL_THRESHOLD the system volume
     * stays at max and LoudnessEnhancer handles everything.  Below it we
     * fade the system volume toward 0 for true silence.
     *
     * @param gainDb gain in dB (e.g. -30 to +30)
     */
    public static void setGain(float gainDb) {
        currentGainDb = gainDb;
        if (!dvcActive || audioManager == null) return;

        int maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC);

        if (gainDb <= MUTE_THRESHOLD) {
            // True silence
            suppressObserver = true;
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, 0, 0);
            suppressObserver = false;
            LoudnessControl.setTargetGain(0);
        } else if (gainDb < SYSTEM_VOL_THRESHOLD) {
            // Crossover zone: map [MUTE, THRESHOLD) -> system vol [0, max]
            float ratio = (gainDb - MUTE_THRESHOLD) / (SYSTEM_VOL_THRESHOLD - MUTE_THRESHOLD);
            int sysVol = Math.round(ratio * maxVol);
            sysVol = Math.max(0, Math.min(maxVol, sysVol));
            suppressObserver = true;
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, sysVol, 0);
            suppressObserver = false;
            // LoudnessEnhancer at 0 in this zone — system vol does the work
            LoudnessControl.setTargetGain(0);
        } else {
            // Normal zone: system at max, LoudnessEnhancer controls gain
            int current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC);
            if (current != maxVol) {
                suppressObserver = true;
                audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, maxVol, 0);
                suppressObserver = false;
            }
            // Convert dB to millibels for LoudnessEnhancer
            LoudnessControl.setTargetGain(Math.round(gainDb * 100));
        }
    }

    /**
     * Forward a hardware volume-button press as a DVC gain adjustment.
     * Called from MainActivity.onKeyDown.
     *
     * @param direction "up" or "down"
     * @return true if the event was consumed (DVC is active)
     */
    public static boolean onVolumeButton(String direction) {
        if (!dvcActive) return false;

        // Send event to Flutter (Dart side adjusts gainDb and calls setGain)
        if (eventSink != null) {
            eventSink.success(direction);
        }
        return true;
    }

    public static boolean isActive() {
        return dvcActive;
    }

    public static int getSavedVolume() {
        return savedSystemVolume;
    }

    public static int getMaxVolume() {
        if (audioManager == null) return 15;
        return audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
    }

    public static int getCurrentSystemVolume() {
        if (audioManager == null) return 0;
        return audioManager.getStreamVolume(AudioManager.STREAM_MUSIC);
    }

    // -- Volume observer --

    private static void registerVolumeObserver(Context context) {
        if (volumeObserver != null) return;
        volumeObserver = new ContentObserver(handler) {
            @Override
            public void onChange(boolean selfChange) {
                if (suppressObserver || !dvcActive || audioManager == null) return;
                // Re-apply the correct system volume for current gain level
                setGain(currentGainDb);
            }
        };
        context.getContentResolver().registerContentObserver(
                Settings.System.CONTENT_URI, true, volumeObserver);
    }

    private static void unregisterVolumeObserver(Context context) {
        if (volumeObserver != null) {
            try {
                context.getContentResolver().unregisterContentObserver(volumeObserver);
            } catch (Exception ignored) {}
            volumeObserver = null;
        }
    }
}
