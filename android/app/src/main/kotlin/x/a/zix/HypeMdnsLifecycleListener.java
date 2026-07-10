package x.a.zix;

import android.content.Context;

import androidx.annotation.Nullable;

import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener;
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/**
 * Attaches the {@link HypeMdnsChannel} to the flutter_foreground_task background
 * {@code FlutterEngine} the moment it's created — which happens before the Dart
 * task's {@code onStart} runs — so the sharing server, running in that isolate,
 * can drive native NsdManager/MulticastLock over the channel.
 *
 * <p>Registered process-wide from {@link HypeApplication}, which runs on every
 * process start (including an activity-less restart of the service by the OS,
 * where {@code MainActivity} never runs). Cleans up the advertisement and
 * multicast lock when the engine is torn down (sharing stopped).
 */
final class HypeMdnsLifecycleListener implements FlutterForegroundTaskLifecycleListener {
    private static HypeMdnsLifecycleListener sInstance;

    private final Context appContext;
    @Nullable private MethodChannel channel;

    private HypeMdnsLifecycleListener(Context appContext) {
        this.appContext = appContext.getApplicationContext();
    }

    static synchronized HypeMdnsLifecycleListener getInstance(Context context) {
        if (sInstance == null) {
            sInstance = new HypeMdnsLifecycleListener(context);
        }
        return sInstance;
    }

    @Override
    public void onEngineCreate(@Nullable FlutterEngine flutterEngine) {
        if (flutterEngine == null) return;
        channel = HypeMdnsChannel.attach(
                flutterEngine.getDartExecutor().getBinaryMessenger(), appContext);
    }

    @Override
    public void onTaskStart(FlutterForegroundTaskStarter starter) {}

    @Override
    public void onTaskRepeatEvent() {}

    @Override
    public void onTaskDestroy() {}

    @Override
    public void onEngineWillDestroy() {
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
        // The server stopped along with the isolate — make sure we don't leave a
        // stale advertisement or a held multicast lock behind. (The Dart side
        // also does this in StreamServerController.stop(); both are idempotent.)
        HypeMdns.unregister();
        HypeMdns.releaseMulticastLock();
    }
}
