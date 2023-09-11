package com.example.eq_app;

import android.annotation.SuppressLint;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;

import androidx.annotation.Nullable;

public class EngineService extends Service {
    String m = "myChannel";
    @SuppressLint("NewApi")
    private void a() {
        DSPEngine.initDSPEngine();
        if (Build.VERSION.SDK_INT >= 26) {
            String string = "HYPE MUZIKI";
            String string2 = "Enjoy hype music";
            NotificationChannel notificationChannel = new NotificationChannel(this.m, string, NotificationManager.IMPORTANCE_LOW);
            notificationChannel.setDescription(string2);
            notificationChannel.setShowBadge(true);
            ((NotificationManager) getSystemService(NotificationManager.class)).createNotificationChannel(notificationChannel);
        }
    }
    @SuppressLint("NewApi")
    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        DSPEngine.initDSPEngine();
        return null;
    }

    @Override // android.app.Service
    public void onDestroy() {
        super.onDestroy();
    }


    @SuppressLint("NewApi")
    @Override // android.app.Service
    public void onCreate() {
        super.onCreate();
            a();
            DSPEngine.initDSPEngine();
            DSPEngine.assignBandGains();
    }

    @SuppressLint("NewApi")
    @Override // android.app.Service
    public int onStartCommand(Intent intent, int i, int i2) {
           DSPEngine.initDSPEngine();
            stopForeground(false);
            stopSelf();
            return Service.START_REDELIVER_INTENT;
    }
}
