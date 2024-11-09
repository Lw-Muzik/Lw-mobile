package x.a.zix;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.graphics.BitmapFactory;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;
//import android.support.v4.app.NotificationCompat;

//import androidx.core.app.NotificationCompat;

public class EngineService extends Service {
    String m = "myChannel";
    private static final int NOTIFICATION_ID = 1;
    private static final String CHANNEL_ID = "MusicPlayerChannel";
    private void a() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            DSPEngine.initDSPEngine();
        }
//        if (Build.VERSION.SDK_INT >= 26) {
//            String string = "HYPE MIZUKI";
//            String string2 = "Enjoy hype music";
//            NotificationChannel notificationChannel = new NotificationChannel(this.m, string, NotificationManager.IMPORTANCE_LOW);
//            notificationChannel.setDescription(string2);
//            notificationChannel.setShowBadge(true);
//            ((NotificationManager) getSystemService(NotificationManager.class)).createNotificationChannel(notificationChannel);
//        }
    }
//    private Notification buildNotification() {
//        Intent intent = new Intent(this, MainActivity.class); // Replace with your app's main activity
//        PendingIntent pendingIntent = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE);

//        NotificationCompat.Builder builder = new NotificationCompat.Builder(this, CHANNEL_ID)
//                .setContentTitle("Music Player")
//                .setContentText("Now playing your music")
//                .setSmallIcon(R.drawable.splash)
//                .setLargeIcon(BitmapFactory.decodeResource(getResources(), R.drawable.splash))
//                .setContentIntent(pendingIntent)
//                .setStyle(new androidx.media.app.NotificationCompat.MediaStyle()
//                        .setShowActionsInCompactView(0, 1, 2)
//                        .setMediaSession(null)) // Pass your media session here if you have one
//                .addAction(android.R.drawable.ic_media_previous, "Previous", null) // Add your actions
//                .addAction(mediaPlayer.isPlaying()
//                        ? android.R.drawable.ic_media_pause
//                        : android.R.drawable.ic_media_play, mediaPlayer.isPlaying() ? "Pause" : "Play", null)
//                .addAction(android.R.drawable.ic_media_next, "Next", null)
//                .setPriority(NotificationCompat.PRIORITY_DEFAULT);

//        return builder.build();
//    }
//    private void createNotificationChannel() {
//        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
//            NotificationChannel channel = new NotificationChannel(
//                    CHANNEL_ID,
//                    "Music Player Channel",
//                    NotificationManager.IMPORTANCE_DEFAULT
//            );
//            NotificationManager manager = getSystemService(NotificationManager.class);
//            manager.createNotificationChannel(channel);
//        }
//    }
    @Override
    public IBinder onBind(Intent intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            DSPEngine.initDSPEngine();
        }
        return null;
    }

    @Override // android.app.Service
    public void onDestroy() {
        super.onDestroy();
    }


    @Override // android.app.Service
    public void onCreate() {
        super.onCreate();
//        createNotificationChannel();
            a();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            Log.e("ESERVICE","Created and running");

            DSPEngine.initDSPEngine();
        }
//            DSPEngine.assignBandGains();
    }
    @Override // android.app.Service
    public int onStartCommand(Intent intent, int i, int i2) {
//            stopForeground(true);
            stopSelf();
//        Notification notification = buildNotification();
//        startForeground(NOTIFICATION_ID, notification);
           return Service.START_STICKY;
    }
}
