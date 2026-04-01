package x.a.zix;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import android.util.Log;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;

/**
 * Lightweight foreground service that shows a persistent notification
 * when the app is running in Equalizer mode. Displays the current
 * EQ preset name and lets the user tap to return to the app.
 */
public class EqModeService extends Service {
    private static final String TAG = "EqModeService";
    private static final String CHANNEL_ID = "eq_mode_channel";
    private static final int NOTIFICATION_ID = 9003;

    public static final String EXTRA_PRESET = "preset";
    public static final String ACTION_UPDATE_PRESET = "x.a.zix.UPDATE_EQ_PRESET";

    private String currentPreset = "Flat";

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        startForeground(NOTIFICATION_ID, buildNotification(currentPreset));
        Log.i(TAG, "EqModeService started");
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null) {
            String preset = intent.getStringExtra(EXTRA_PRESET);
            if (preset != null) {
                currentPreset = preset;
            }
            // Update notification with current preset
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) {
                nm.notify(NOTIFICATION_ID, buildNotification(currentPreset));
            }
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        Log.i(TAG, "EqModeService stopped");
        super.onDestroy();
    }

    @Override
    public void onTaskRemoved(Intent rootIntent) {
        // Keep running when app is swiped from recents
        Log.i(TAG, "Task removed but EqModeService continues");
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void createNotificationChannel() {
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "Equalizer Mode",
                NotificationManager.IMPORTANCE_LOW
        );
        channel.setDescription("Shows when Hype is running in equalizer mode");
        channel.setShowBadge(false);

        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) nm.createNotificationChannel(channel);
    }

    private Notification buildNotification(String preset) {
        // Tap notification → open app
        Intent launchIntent = getPackageManager().getLaunchIntentForPackage(getPackageName());
        PendingIntent launchPi = launchIntent != null
                ? PendingIntent.getActivity(this, 0, launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE)
                : null;

        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("Hype EQ Running")
                .setContentText("Preset: " + preset)
                .setSmallIcon(R.drawable.ic_stat_eq)
                .setOngoing(true)
                .setContentIntent(launchPi)
                .build();
    }
}
