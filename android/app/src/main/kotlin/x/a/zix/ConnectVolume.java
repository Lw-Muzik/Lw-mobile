package x.a.zix;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.media.AudioManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

/**
 * The phone's media volume, for Hype Connect.
 *
 * <p>When this phone is the player, the volume the listener hears is the
 * system MEDIA stream (or the DVC gain, which Dart handles itself) - not the
 * just_audio gain, which ReplayGain, video loads and crossfades keep rewriting.
 * This reads, sets and watches that stream, and carries the one extra piece of
 * the other direction: when this phone is only a REMOTE for another device, its
 * hardware volume keys must step that device's volume rather than the phone's
 * own (silent) one, so {@link #sRemoteKeys} lets {@code MainActivity} divert
 * them to Dart.
 *
 * <p>Everything uses the application context, so it works on the headless
 * engine {@link ConnectService} starts after a reboot as well.
 */
final class ConnectVolume {
    private static final String TAG = "ConnectVolume";

    /** The system broadcast for any stream's volume change; not in the SDK. */
    private static final String VOLUME_CHANGED_ACTION = "android.media.VOLUME_CHANGED_ACTION";
    private static final String EXTRA_VOLUME_STREAM_TYPE = "android.media.EXTRA_VOLUME_STREAM_TYPE";

    /**
     * Hardware volume keys are diverted to Dart (a remote device's volume).
     * Read on the UI thread by the activity, written from the channel handler.
     */
    static volatile boolean sRemoteKeys = false;

    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    private static BroadcastReceiver sReceiver;
    private static Context sApp;

    private ConnectVolume() {}

    private static AudioManager audio(Context context) {
        return (AudioManager) context.getApplicationContext().getSystemService(Context.AUDIO_SERVICE);
    }

    /** The media stream's volume as 0..1; 1 when the platform cannot say. */
    static double get(Context context) {
        AudioManager am = audio(context);
        if (am == null) return 1.0;
        int max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
        if (max <= 0) return 1.0;
        return am.getStreamVolume(AudioManager.STREAM_MUSIC) / (double) max;
    }

    /**
     * Sets the media stream's volume from 0..1. Flags 0: no system panel and no
     * click, since the person who asked is on another device.
     */
    static void set(Context context, double value) {
        AudioManager am = audio(context);
        if (am == null) return;
        int max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
        double clamped = Math.max(0.0, Math.min(1.0, value));
        am.setStreamVolume(AudioManager.STREAM_MUSIC, (int) Math.round(clamped * max), 0);
    }

    /** Starts or stops forwarding media-volume changes to Dart. Idempotent. */
    static synchronized void watch(Context context, boolean on) {
        if (on) {
            if (sReceiver != null) return;
            final Context app = context.getApplicationContext();
            sApp = app;
            sReceiver = new BroadcastReceiver() {
                @Override
                public void onReceive(Context ctx, Intent intent) {
                    if (intent == null) return;
                    int type = intent.getIntExtra(EXTRA_VOLUME_STREAM_TYPE, -1);
                    if (type != AudioManager.STREAM_MUSIC) return;
                    final double value = get(app);
                    // Receivers run on the main thread already; posting keeps
                    // the invoke there if a ROM ever delivers elsewhere.
                    MAIN.post(() -> ConnectChannel.sendVolumeChanged(value));
                }
            };
            IntentFilter filter = new IntentFilter(VOLUME_CHANGED_ACTION);
            if (Build.VERSION.SDK_INT >= 33) {
                // A system broadcast, so it has to be exported to be heard.
                app.registerReceiver(sReceiver, filter, Context.RECEIVER_EXPORTED);
            } else {
                app.registerReceiver(sReceiver, filter);
            }
        } else {
            unregister();
        }
    }

    private static void unregister() {
        if (sReceiver == null) return;
        try {
            if (sApp != null) sApp.unregisterReceiver(sReceiver);
        } catch (RuntimeException e) {
            Log.w(TAG, "unregister failed", e);
        }
        sReceiver = null;
        sApp = null;
    }

    /** Whether a key event is one the remote-keys mode consumes. */
    static boolean isRemoteKey(int keyCode) {
        return sRemoteKeys && (keyCode == android.view.KeyEvent.KEYCODE_VOLUME_UP
                || keyCode == android.view.KeyEvent.KEYCODE_VOLUME_DOWN);
    }
}
