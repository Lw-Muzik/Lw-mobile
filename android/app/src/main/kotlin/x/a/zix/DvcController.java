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
 * A {@link ContentObserver} watches for external volume changes (e.g. the
 * user pressing hardware buttons in Settings or another app) and re-forces
 * max volume, forwarding the event to Flutter so the DVC gain slider can
 * respond instead.
 */
public class DvcController {

    private static AudioManager audioManager;
    private static int savedSystemVolume = -1;
    private static boolean dvcActive = false;
    private static ContentObserver volumeObserver;
    private static Handler handler;
    private static boolean suppressObserver = false;

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
     * Forward a hardware volume-button press as a DVC gain adjustment.
     * Called from MainActivity.onKeyDown.
     *
     * @param direction "up" or "down"
     * @return true if the event was consumed (DVC is active)
     */
    public static boolean onVolumeButton(String direction) {
        if (!dvcActive) return false;

        // Re-force max in case something changed
        if (audioManager != null) {
            int maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
            int current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC);
            if (current != maxVol) {
                suppressObserver = true;
                audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, maxVol, 0);
                suppressObserver = false;
            }
        }

        // Send event to Flutter
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
                int current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC);
                int maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
                if (current != maxVol) {
                    // Something changed volume externally — re-force max
                    suppressObserver = true;
                    audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, maxVol, 0);
                    suppressObserver = false;
                }
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
