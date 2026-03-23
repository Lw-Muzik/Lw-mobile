package x.a.zix;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.media.AudioManager;
import android.media.AudioPlaybackConfiguration;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import androidx.core.app.NotificationCompat;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * Foreground service that attaches a global DynamicsProcessing EQ to the audio
 * output mix (sessionId = 0), applying the current EQ profile to ALL audio apps.
 *
 * Per-session attachment to external apps requires system-level permissions on
 * Android 10+. Using sessionId = 0 is the standard third-party EQ approach.
 *
 * Also tracks which apps are currently playing (for UI display) via the public
 * AudioPlaybackCallback API (no reflection required).
 *
 * Note: To prevent double-EQ on own app's audio, the C++ DSP EQ is bypassed
 * while this service is active (handled by RoomEffectsProcessor.broadcastGlobalEqActive).
 */
@RequiresApi(api = Build.VERSION_CODES.P)
public class GlobalEqService extends Service {
    private static final String TAG = "GlobalEqService";
    private static final String CHANNEL_ID = "global_eq_channel";
    private static final int NOTIFICATION_ID = 9002;
    private static final String ACTION_STOP = "x.a.zix.STOP_GLOBAL_EQ";

    private AudioManager audioManager;
    private AudioManager.AudioPlaybackCallback playbackCallback;
    private final Handler handler = new Handler(Looper.getMainLooper());

    // Currently playing app package names (for UI display only)
    private static final CopyOnWriteArrayList<String> playingApps = new CopyOnWriteArrayList<>();

    /** Returns a snapshot of currently playing app package names. */
    public static List<String> getPlayingApps() {
        return new ArrayList<>(playingApps);
    }

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        startForeground(NOTIFICATION_ID, buildNotification());

        audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);

        // Attach global DynamicsProcessing to output mix
        GlobalEqSessionManager.setEnabled(true);
        GlobalEqSessionManager.attachGlobal();

        // Bypass C++ EQ in own app to prevent double-processing
        RoomEffectsProcessor.broadcastGlobalEqActive(true);

        // Track playing apps for UI display (public API, no reflection)
        registerPlaybackCallback();
        scanPlayingApps();

        Log.i(TAG, "GlobalEqService started — global output mix EQ active");
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && ACTION_STOP.equals(intent.getAction())) {
            stopSelf();
            return START_NOT_STICKY;
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        unregisterPlaybackCallback();
        playingApps.clear();
        GlobalEqSessionManager.setEnabled(false);
        GlobalEqSessionManager.releaseAll();
        // Restore C++ EQ for own app
        RoomEffectsProcessor.broadcastGlobalEqActive(false);
        Log.i(TAG, "GlobalEqService stopped");
        super.onDestroy();
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    // ---- AudioPlaybackCallback (display-only: tracks which apps are playing) ----

    private void registerPlaybackCallback() {
        if (audioManager == null) return;

        playbackCallback = new AudioManager.AudioPlaybackCallback() {
            @Override
            public void onPlaybackConfigChanged(List<AudioPlaybackConfiguration> configs) {
                updatePlayingApps(configs);
            }
        };
        audioManager.registerAudioPlaybackCallback(playbackCallback, handler);
    }

    private void unregisterPlaybackCallback() {
        if (audioManager != null && playbackCallback != null) {
            try {
                audioManager.unregisterAudioPlaybackCallback(playbackCallback);
            } catch (Exception ignored) {}
            playbackCallback = null;
        }
    }

    /** Scan for already-active playback sessions on startup. */
    private void scanPlayingApps() {
        if (audioManager == null) return;
        try {
            List<AudioPlaybackConfiguration> configs =
                    audioManager.getActivePlaybackConfigurations();
            if (configs != null) {
                updatePlayingApps(configs);
            }
        } catch (Exception e) {
            Log.w(TAG, "Failed to scan active playback configs: " + e.getMessage());
        }
    }

    /**
     * Rebuild the playing-apps list from the current set of active configs.
     * Uses the public getClientPackageName() API — no reflection needed.
     * Skips our own package to avoid showing Hype in the "other apps" list.
     */
    private void updatePlayingApps(List<AudioPlaybackConfiguration> configs) {
        if (configs == null) return;

        List<String> active = new ArrayList<>();
        String ownPkg = getPackageName();

        for (AudioPlaybackConfiguration config : configs) {
            String pkg = config.getClientPackageName();
            if (pkg != null && !pkg.equals(ownPkg) && !active.contains(pkg)) {
                active.add(pkg);
            }
        }

        playingApps.clear();
        playingApps.addAll(active);
    }

    // ---- Notification ----

    private void createNotificationChannel() {
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "Global Equalizer",
                NotificationManager.IMPORTANCE_LOW
        );
        channel.setDescription("Shows when Hype EQ is applied to all apps");
        channel.setShowBadge(false);

        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) nm.createNotificationChannel(channel);
    }

    private Notification buildNotification() {
        // "Turn Off" action
        Intent stopIntent = new Intent(this, GlobalEqService.class);
        stopIntent.setAction(ACTION_STOP);
        PendingIntent stopPi = PendingIntent.getService(
                this, 0, stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        // Tap notification → open app
        Intent launchIntent = getPackageManager().getLaunchIntentForPackage(getPackageName());
        PendingIntent launchPi = launchIntent != null
                ? PendingIntent.getActivity(this, 0, launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE)
                : null;

        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("Hype EQ Active")
                .setContentText("Equalizer applied to all apps")
                .setSmallIcon(R.drawable.ic_stat_eq)
                .setOngoing(true)
                .setContentIntent(launchPi)
                .addAction(R.drawable.ic_stat_eq, "Turn Off", stopPi)
                .build();
    }
}
