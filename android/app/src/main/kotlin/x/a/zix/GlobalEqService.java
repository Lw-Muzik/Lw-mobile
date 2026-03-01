package x.a.zix;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.media.AudioManager;
import android.media.AudioPlaybackConfiguration;
import android.media.audiofx.AudioEffect;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import androidx.core.app.NotificationCompat;

import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * Foreground service that discovers audio sessions from ALL apps (including Spotify)
 * and attaches DynamicsProcessing EQ via GlobalEqSessionManager.
 *
 * Uses two discovery mechanisms:
 * 1. AudioPlaybackCallback (primary) — actively monitors all playback sessions via AudioManager.
 *    This catches apps like Spotify that don't broadcast session events.
 *    Uses reflection on hidden AudioPlaybackConfiguration.getAudioSessionId().
 * 2. BroadcastReceiver (fallback) — listens for ACTION_OPEN/CLOSE_AUDIO_EFFECT_CONTROL_SESSION
 *    for apps that do broadcast (older MediaPlayer-based apps).
 */
@RequiresApi(api = Build.VERSION_CODES.P)
public class GlobalEqService extends Service {
    private static final String TAG = "GlobalEqService";
    private static final String CHANNEL_ID = "global_eq_channel";
    private static final int NOTIFICATION_ID = 9002;
    private static final String ACTION_STOP = "x.a.zix.STOP_GLOBAL_EQ";

    private BroadcastReceiver sessionReceiver;
    private AudioManager audioManager;
    private AudioManager.AudioPlaybackCallback playbackCallback;
    private final Handler handler = new Handler(Looper.getMainLooper());

    // Sessions discovered via playback callback (reflection-based)
    private final Set<Integer> callbackSessions = new HashSet<>();
    // Sessions discovered via broadcast receiver
    private final Set<Integer> broadcastSessions = new HashSet<>();

    // Cache reflected methods to avoid repeated lookups
    private static java.lang.reflect.Method getAudioSessionIdMethod;
    private static java.lang.reflect.Method getClientUidMethod;
    private static boolean reflectionAttempted = false;
    private int ownUid = -1;

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        startForeground(NOTIFICATION_ID, buildNotification());
        GlobalEqSessionManager.setEnabled(true);

        audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        ownUid = android.os.Process.myUid();

        // Primary: AudioPlaybackCallback — catches Spotify and all other apps
        registerPlaybackCallback();

        // Fallback: BroadcastReceiver — catches apps that broadcast session events
        registerSessionReceiver();

        // Scan for already-playing sessions (e.g. Spotify already playing when we start)
        scanActiveSessions();

        Log.i(TAG, "GlobalEqService started");
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
        unregisterSessionReceiver();
        GlobalEqSessionManager.setEnabled(false);
        GlobalEqSessionManager.releaseAll();
        callbackSessions.clear();
        broadcastSessions.clear();
        Log.i(TAG, "GlobalEqService stopped");
        super.onDestroy();
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    // ---- AudioPlaybackCallback (primary session discovery) ----

    private void registerPlaybackCallback() {
        if (audioManager == null) return;

        playbackCallback = new AudioManager.AudioPlaybackCallback() {
            @Override
            public void onPlaybackConfigChanged(List<AudioPlaybackConfiguration> configs) {
                handlePlaybackConfigChanged(configs);
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

    /**
     * Called whenever any app's playback state changes.
     * Discovers new sessions via reflection and detaches ended ones.
     */
    private void handlePlaybackConfigChanged(List<AudioPlaybackConfiguration> configs) {
        if (configs == null) return;

        Set<Integer> activeSessions = new HashSet<>();

        for (AudioPlaybackConfiguration config : configs) {
            // Skip our own app's sessions (already processed by C++ DSP pipeline)
            int clientUid = getClientUidFromConfig(config);
            if (clientUid == ownUid) continue;

            int sessionId = getSessionIdFromConfig(config);
            if (sessionId <= 0) continue;

            activeSessions.add(sessionId);

            if (!callbackSessions.contains(sessionId) && !broadcastSessions.contains(sessionId)) {
                callbackSessions.add(sessionId);
                Log.i(TAG, "Playback session discovered: " + sessionId);
                GlobalEqSessionManager.attachSession(sessionId, "playback-callback");
            }
        }

        // Detach callback-discovered sessions that are no longer active
        Set<Integer> removed = new HashSet<>();
        for (int sessionId : callbackSessions) {
            if (!activeSessions.contains(sessionId)) {
                removed.add(sessionId);
            }
        }
        for (int sessionId : removed) {
            callbackSessions.remove(sessionId);
            Log.i(TAG, "Playback session ended: " + sessionId);
            GlobalEqSessionManager.detachSession(sessionId);
        }
    }

    /**
     * Extract audio session ID from AudioPlaybackConfiguration via reflection.
     * The getAudioSessionId() method is @hide but present on all Android 9+ devices.
     * Returns the session ID, or -1 if reflection fails.
     */
    private static int getSessionIdFromConfig(AudioPlaybackConfiguration config) {
        initReflection();
        if (getAudioSessionIdMethod == null) return -1;

        try {
            Object result = getAudioSessionIdMethod.invoke(config);
            if (result instanceof Integer) {
                return (Integer) result;
            }
        } catch (Exception e) {
            Log.w(TAG, "getAudioSessionId() invoke failed: " + e.getMessage());
        }

        return -1;
    }

    /**
     * Extract client UID from AudioPlaybackConfiguration via reflection.
     * Used to filter out our own app's sessions.
     * Returns -1 if reflection fails.
     */
    private static int getClientUidFromConfig(AudioPlaybackConfiguration config) {
        initReflection();
        if (getClientUidMethod == null) return -1;

        try {
            Object result = getClientUidMethod.invoke(config);
            if (result instanceof Integer) {
                return (Integer) result;
            }
        } catch (Exception e) {
            // Not critical — worst case we attach to own session and it's a no-op
        }

        return -1;
    }

    /** Initialize reflection methods once. */
    private static void initReflection() {
        if (reflectionAttempted) return;
        reflectionAttempted = true;

        try {
            getAudioSessionIdMethod = AudioPlaybackConfiguration.class
                    .getDeclaredMethod("getAudioSessionId");
            getAudioSessionIdMethod.setAccessible(true);
            Log.i(TAG, "Reflection: getAudioSessionId() available");
        } catch (NoSuchMethodException e) {
            Log.w(TAG, "getAudioSessionId() not found — playback callback discovery won't work");
            getAudioSessionIdMethod = null;
        }

        try {
            getClientUidMethod = AudioPlaybackConfiguration.class
                    .getDeclaredMethod("getClientUid");
            getClientUidMethod.setAccessible(true);
        } catch (NoSuchMethodException e) {
            getClientUidMethod = null;
        }
    }

    /** Scan for already-active playback sessions on startup. */
    private void scanActiveSessions() {
        if (audioManager == null) return;
        try {
            List<AudioPlaybackConfiguration> configs =
                    audioManager.getActivePlaybackConfigurations();
            if (configs != null && !configs.isEmpty()) {
                Log.i(TAG, "Scanning " + configs.size() + " active playback sessions");
                handlePlaybackConfigChanged(configs);
            }
        } catch (Exception e) {
            Log.w(TAG, "Failed to scan active sessions: " + e.getMessage());
        }
    }

    // ---- BroadcastReceiver (fallback session discovery) ----

    private void registerSessionReceiver() {
        sessionReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                if (intent == null || intent.getAction() == null) return;

                int sessionId = intent.getIntExtra(AudioEffect.EXTRA_AUDIO_SESSION, -1);
                String pkg = intent.getStringExtra(AudioEffect.EXTRA_PACKAGE_NAME);
                if (sessionId <= 0) return;

                // Skip our own sessions to prevent double-processing
                if (getPackageName().equals(pkg)) return;

                switch (intent.getAction()) {
                    case AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION:
                        Log.i(TAG, "Broadcast session opened: " + sessionId + " (" + pkg + ")");
                        broadcastSessions.add(sessionId);
                        GlobalEqSessionManager.attachSession(sessionId, pkg);
                        break;
                    case AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION:
                        Log.i(TAG, "Broadcast session closed: " + sessionId + " (" + pkg + ")");
                        broadcastSessions.remove(sessionId);
                        GlobalEqSessionManager.detachSession(sessionId);
                        break;
                }
            }
        };

        IntentFilter filter = new IntentFilter();
        filter.addAction(AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION);
        filter.addAction(AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(sessionReceiver, filter, Context.RECEIVER_EXPORTED);
        } else {
            registerReceiver(sessionReceiver, filter);
        }
    }

    private void unregisterSessionReceiver() {
        if (sessionReceiver != null) {
            try {
                unregisterReceiver(sessionReceiver);
            } catch (Exception ignored) {}
            sessionReceiver = null;
        }
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
