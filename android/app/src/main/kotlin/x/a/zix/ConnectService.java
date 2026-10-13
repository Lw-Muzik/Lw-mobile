package x.a.zix;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.content.SharedPreferences;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

import androidx.annotation.Nullable;

import com.ryanheise.audioservice.AudioService;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Foreground service that keeps Hype Connect reachable while the app is in the
 * background, with a persistent notification saying what is happening.
 *
 * <p>The service itself holds no socket: the WebSocket lives in the Dart
 * isolate (HypeConnect). What this service gives is a process Android will not
 * freeze or reclaim, and the notification the user sees and can turn it off
 * from. The words and buttons are worked out in Dart
 * ({@code connect_notification.dart}) and pushed here through
 * {@link ConnectChannel}; button taps go back the same way.
 *
 * <p>Start rules (Android 12+ forbids starting a foreground service from the
 * background): Dart starts it while the app is on screen; {@link
 * ConnectBootReceiver} starts it after a reboot or an app update, both of
 * which are exempt. A system restart of a killed service (START_STICKY, null
 * intent) is honoured only while the "wanted" flag Dart mirrors into
 * preferences is still set, so a service the user turned off never comes back.
 * Every start also makes sure the Flutter engine that runs {@code main()} is up
 * — after a reboot there is no activity to create it.
 */
public class ConnectService extends Service {
    private static final String TAG = "ConnectService";
    static final String CHANNEL_ID = "hype_connect";
    private static final int NOTIFICATION_ID = 9004;

    static final String ACTION_START = "x.a.zix.CONNECT_START";
    static final String ACTION_BUTTON = "x.a.zix.CONNECT_BUTTON";
    static final String EXTRA_BUTTON = "button";
    /** Put on the launch intent of the notification tap; read by {@link ConnectChannel}. */
    static final String EXTRA_OPEN_CONNECT = "x.a.zix.OPEN_HYPE_CONNECT";

    private static final String PREFS = "hype_connect_native";
    private static final String KEY_WANTED = "wanted";

    private static volatile ConnectService sInstance;

    /**
     * Held while the service runs so audio_service's {@link AudioService} is
     * never left with no client. Swiping the app away unbinds the activity;
     * when nothing has played, AudioService is bound-only, so Android destroys
     * it, and its onDestroy destroys the shared Flutter engine
     * (AudioServicePlugin.disposeFlutterEngine) — the isolate that holds the
     * Hype Connect socket. Device-tested: without this binding the phone fell
     * off the hub one ping timeout (~47 s) after every swipe-away.
     */
    private final ServiceConnection audioKeepAlive = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder service) {
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
        }
    };
    private boolean audioBound;

    /** What the notification says. Survives the service so a restart can show it at once. */
    private static volatile Content sContent = Content.placeholder();

    /** One notification's worth of words and buttons, as Dart sent them. */
    static final class Content {
        final String title;
        @Nullable final String text;
        @Nullable final String subText;
        /** previous, pause, play, next, turnOff. */
        final List<String> actions;

        Content(String title, @Nullable String text, @Nullable String subText, List<String> actions) {
            this.title = title;
            this.text = text;
            this.subText = subText;
            this.actions = actions;
        }

        static Content placeholder() {
            List<String> actions = new ArrayList<>();
            actions.add("turnOff");
            return new Content("Hype Connect", "Starting…", null, actions);
        }

        static Content fromMap(Map<?, ?> map) {
            List<String> actions = new ArrayList<>();
            Object raw = map.get("actions");
            if (raw instanceof List) {
                for (Object o : (List<?>) raw) actions.add(String.valueOf(o));
            }
            if (actions.isEmpty()) actions.add("turnOff");
            Object title = map.get("title");
            return new Content(
                    title == null ? "Hype Connect" : String.valueOf(title),
                    map.get("text") == null ? null : String.valueOf(map.get("text")),
                    map.get("subText") == null ? null : String.valueOf(map.get("subText")),
                    actions);
        }
    }

    // ------------------------------------------------------------------
    // Static API, used by ConnectChannel and ConnectBootReceiver
    // ------------------------------------------------------------------

    static boolean isRunning() {
        return sInstance != null;
    }

    /**
     * Starts the service. Returns false when Android refused — an app that is
     * not in a state allowed to start a foreground service (Android 12+) — so
     * the Dart side can try again when the app is next on screen.
     */
    static boolean start(Context context) {
        Context app = context.getApplicationContext();
        Intent intent = new Intent(app, ConnectService.class).setAction(ACTION_START);
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                app.startForegroundService(intent);
            } else {
                app.startService(intent);
            }
            return true;
        } catch (RuntimeException e) {
            // ForegroundServiceStartNotAllowedException (API 31+) is an
            // IllegalStateException; a SecurityException means the manifest or
            // permissions are wrong. Neither may take the app down.
            Log.w(TAG, "could not start the foreground service", e);
            return false;
        }
    }

    static void stop(Context context) {
        Context app = context.getApplicationContext();
        app.stopService(new Intent(app, ConnectService.class));
    }

    static void update(Content content) {
        sContent = content;
        ConnectService service = sInstance;
        if (service != null) service.showNotification();
    }

    static void setWanted(Context context, boolean wanted) {
        context.getApplicationContext()
                .getSharedPreferences(PREFS, MODE_PRIVATE)
                .edit().putBoolean(KEY_WANTED, wanted).apply();
    }

    static boolean isWanted(Context context) {
        return context.getApplicationContext()
                .getSharedPreferences(PREFS, MODE_PRIVATE)
                .getBoolean(KEY_WANTED, false);
    }

    // ------------------------------------------------------------------
    // Service
    // ------------------------------------------------------------------

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        // A null intent is the system restarting a killed service. Only the
        // flag Dart mirrors says whether anyone still wants it.
        boolean explicit = intent != null && ACTION_START.equals(intent.getAction());
        boolean button = intent != null && ACTION_BUTTON.equals(intent.getAction());
        if (!explicit && !isWanted(this)) {
            // Started by something stale (a leftover notification button, a
            // restart after the user turned it off). If it was started with
            // startForegroundService it still owes a startForeground call.
            if (!button || sInstance == null) {
                goForeground();
                stopSelf();
                return START_NOT_STICKY;
            }
        }

        goForeground();
        // The Dart isolate that holds the socket must be running. With an
        // activity it already is; after a reboot or a system restart nothing
        // else will create it.
        try {
            ConnectChannel.ensureEngine(this);
        } catch (Throwable t) {
            Log.e(TAG, "could not start the Flutter engine", t);
        }
        holdAudioService();
        if (button) {
            String id = intent.getStringExtra(EXTRA_BUTTON);
            if (id != null) ConnectChannel.sendAction(id);
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        releaseAudioService();
        if (sInstance == this) sInstance = null;
        Log.i(TAG, "ConnectService stopped");
        super.onDestroy();
    }

    @Override
    public void onTaskRemoved(Intent rootIntent) {
        // Swiping the app from recents must not end Hype Connect: that is the
        // point of the service (android:stopWithTask="false" in the manifest).
        Log.i(TAG, "Task removed but ConnectService continues");
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void holdAudioService() {
        if (audioBound) return;
        try {
            // The MediaBrowserService action, so onBind hands back a binder.
            Intent intent = new Intent("android.media.browse.MediaBrowserService")
                    .setComponent(new ComponentName(this, AudioService.class));
            audioBound = bindService(intent, audioKeepAlive, Context.BIND_AUTO_CREATE);
        } catch (RuntimeException e) {
            Log.w(TAG, "could not bind AudioService", e);
        }
    }

    private void releaseAudioService() {
        if (!audioBound) return;
        audioBound = false;
        try {
            unbindService(audioKeepAlive);
        } catch (IllegalArgumentException e) {
            // Already unbound.
        }
    }

    private void goForeground() {
        Notification notification = buildNotification(sContent);
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE);
            } else {
                startForeground(NOTIFICATION_ID, notification);
            }
            sInstance = this;
        } catch (RuntimeException e) {
            // Not allowed from the background (Android 12+), or the type's
            // permission is missing. Say so and stand down rather than crash.
            Log.w(TAG, "startForeground refused", e);
            stopSelf();
        }
    }

    private void showNotification() {
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) nm.notify(NOTIFICATION_ID, buildNotification(sContent));
    }

    private void createNotificationChannel() {
        // NotificationChannel only exists on API 26+ (minSdk is 24); pre-O
        // foreground services don't need one.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID, "Hype Connect", NotificationManager.IMPORTANCE_LOW);
        channel.setDescription("Shows while Hype Connect keeps this phone reachable from your other devices");
        channel.setShowBadge(false);
        channel.setSound(null, null);
        channel.enableVibration(false);
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) nm.createNotificationChannel(channel);
    }

    @SuppressWarnings("deprecation")
    private Notification buildNotification(Content content) {
        // The framework builder rather than NotificationCompat: the transport
        // buttons need MediaStyle (up to five actions; a plain notification
        // shows three), and the compat MediaStyle is in androidx.media, which
        // this module does not depend on.
        Notification.Builder builder = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? new Notification.Builder(this, CHANNEL_ID)
                : new Notification.Builder(this).setPriority(Notification.PRIORITY_LOW);
        builder.setSmallIcon(R.drawable.ic_stat_eq)
                .setContentTitle(content.title)
                .setContentText(content.text)
                .setSubText(content.subText)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setCategory(Notification.CATEGORY_SERVICE)
                .setContentIntent(openAppIntent());
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE);
        }

        int transport = 0;
        for (String name : content.actions) {
            int icon;
            String label;
            String id;
            switch (name) {
                case "previous":
                    icon = android.R.drawable.ic_media_previous; label = "Previous"; id = "previous"; break;
                case "pause":
                    icon = android.R.drawable.ic_media_pause; label = "Pause"; id = "toggle"; break;
                case "play":
                    icon = android.R.drawable.ic_media_play; label = "Play"; id = "toggle"; break;
                case "next":
                    icon = android.R.drawable.ic_media_next; label = "Next"; id = "next"; break;
                case "turnOff":
                    icon = android.R.drawable.ic_menu_close_clear_cancel; label = "Turn off"; id = "off"; break;
                default:
                    continue;
            }
            if (!"turnOff".equals(name)) transport++;
            builder.addAction(icon, label, buttonIntent(id));
        }
        if (transport > 0) {
            // Previous / play-pause / next stay on the collapsed card; "Turn
            // off" is the fourth button, on the expanded one.
            builder.setStyle(new Notification.MediaStyle().setShowActionsInCompactView(0, 1, 2));
        } else if (content.text != null) {
            builder.setStyle(new Notification.BigTextStyle().bigText(content.text));
        }
        return builder.build();
    }

    private PendingIntent openAppIntent() {
        Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (launch == null) return null;
        launch.putExtra(EXTRA_OPEN_CONNECT, true);
        return PendingIntent.getActivity(this, 1, launch,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private PendingIntent buttonIntent(String id) {
        Intent intent = new Intent(this, ConnectService.class)
                .setAction(ACTION_BUTTON)
                .putExtra(EXTRA_BUTTON, id);
        // One request code per button so their extras are not merged.
        return PendingIntent.getService(this, 100 + Math.abs(id.hashCode() % 100), intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }
}
