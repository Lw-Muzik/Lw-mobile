package x.a.zix;

import android.app.Application;
import android.util.Log;

import com.pravera.flutter_foreground_task.FlutterForegroundTaskPlugin;

/**
 * App {@link Application} whose sole extra job is to register the Phone Link
 * lifecycle listeners process-wide. Doing it here (rather than in
 * {@code MainActivity}) means the native NsdManager advertisement and the
 * MediaStore importer are wired into the flutter_foreground_task background
 * engine whenever the sharing service starts — including an activity-less
 * restart of the service by the OS, where {@code MainActivity} never runs.
 */
public class HypeApplication extends Application {
    @Override
    public void onCreate() {
        super.onCreate();
        try {
            // The companion method isn't @JvmStatic, so it's reached via .Companion.
            // The plugin keeps a list of listeners, so these don't displace each other.
            FlutterForegroundTaskPlugin.Companion.addTaskLifecycleListener(
                    HypeMdnsLifecycleListener.getInstance(this));
            FlutterForegroundTaskPlugin.Companion.addTaskLifecycleListener(
                    HypeMediaStoreLifecycleListener.getInstance(this));
        } catch (Throwable t) {
            // Never let this break app startup — sharing degrades gracefully to
            // its stable-port reconnect path if advertising isn't wired, and
            // /upload fails closed with a 500 if the importer isn't.
            Log.w("HypeApplication", "lifecycle listener registration failed", t);
        }
    }
}
