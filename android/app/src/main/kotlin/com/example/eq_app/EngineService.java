package com.example.eq_app;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

public class EngineService extends Service {
    String m = "myChannel";
    private void a() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            DSPEngine.initDSPEngine();
        }
        if (Build.VERSION.SDK_INT >= 26) {
            String string = "HYPE MUZIKI";
            String string2 = "Enjoy hype music";
            NotificationChannel notificationChannel = new NotificationChannel(this.m, string, NotificationManager.IMPORTANCE_LOW);
            notificationChannel.setDescription(string2);
            notificationChannel.setShowBadge(true);
            ((NotificationManager) getSystemService(NotificationManager.class)).createNotificationChannel(notificationChannel);
        }
    }
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
            a();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            Log.e("ESERVICE","Created and running");

            DSPEngine.initDSPEngine();
        }
//            DSPEngine.assignBandGains();
    }
    @Override // android.app.Service
    public int onStartCommand(Intent intent, int i, int i2) {
            stopForeground(true);
            stopSelf();
            return Service.START_REDELIVER_INTENT;
    }
}
