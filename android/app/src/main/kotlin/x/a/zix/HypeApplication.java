package x.a.zix;

import android.app.Application;
import android.util.Log;

import com.pravera.flutter_foreground_task.FlutterForegroundTaskPlugin;

/**
 * App {@link Application} whose sole extra job is to register the Phone Link
 * mDNS lifecycle listener process-wide. Doing it here (rather than in
 * {@code MainActivity}) means the native NsdManager advertisement is wired into
 * the flutter_foreground_task background engine whenever the sharing service
 * starts — including an activity-less restart of the service by the OS, where
 * {@code MainActivity} never runs.
 */
public class HypeApplication extends Application {
    @Override
    public void onCreate() {
        super.onCreate();
        try {
            // The companion method isn't @JvmStatic, so it's reached via .Companion.
            FlutterForegroundTaskPlugin.Companion.addTaskLifecycleListener(
                    HypeMdnsLifecycleListener.getInstance(this));
        } catch (Throwable t) {
            // Never let this break app startup — sharing degrades gracefully to
            // its stable-port reconnect path if advertising isn't wired.
            Log.w("HypeApplication", "mDNS lifecycle listener registration failed", t);
        }
    }
}
