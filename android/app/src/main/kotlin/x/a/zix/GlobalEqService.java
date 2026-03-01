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
import android.media.audiofx.AudioEffect;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import androidx.core.app.NotificationCompat;

/**
 * Foreground service that listens for audio session broadcasts from other apps
 * and attaches DynamicsProcessing EQ via GlobalEqSessionManager.
 */
@RequiresApi(api = Build.VERSION_CODES.P)
public class GlobalEqService extends Service {
    private static final String TAG = "GlobalEqService";
    private static final String CHANNEL_ID = "global_eq_channel";
    private static final int NOTIFICATION_ID = 9001;
    private static final String ACTION_STOP = "x.a.zix.STOP_GLOBAL_EQ";

    private BroadcastReceiver sessionReceiver;

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        startForeground(NOTIFICATION_ID, buildNotification());
        GlobalEqSessionManager.setEnabled(true);
        registerSessionReceiver();
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
        unregisterSessionReceiver();
        GlobalEqSessionManager.setEnabled(false);
        GlobalEqSessionManager.releaseAll();
        Log.i(TAG, "GlobalEqService stopped");
        super.onDestroy();
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

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
                        Log.d(TAG, "Session opened: " + sessionId + " (" + pkg + ")");
                        GlobalEqSessionManager.attachSession(sessionId, pkg);
                        break;
                    case AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION:
                        Log.d(TAG, "Session closed: " + sessionId + " (" + pkg + ")");
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
