package x.a.zix;

import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import android.util.Log;

public class EngineService extends Service {
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
    }

    @Override
    public void onCreate() {
        super.onCreate();
        Log.i("EngineService", "Created");
    }

    @Override
    public int onStartCommand(Intent intent, int i, int i2) {
        stopSelf();
        return Service.START_STICKY;
    }
}
