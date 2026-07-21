package x.a.zix;

import android.content.Context;

import androidx.annotation.Nullable;

import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener;
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/**
 * Attaches the {@link HypeMediaStoreChannel} to the flutter_foreground_task
 * background {@code FlutterEngine} the moment it's created — which happens
 * before the Dart task's {@code onStart} runs — so the sharing server's
 * {@code POST /upload} endpoint, running in that isolate, can publish received
 * files into MediaStore.
 *
 * <p>Mirrors {@link HypeMdnsLifecycleListener}; the plugin holds a list of
 * listeners, so the two coexist. Registered process-wide from
 * {@link HypeApplication}, which runs on every process start (including an
 * activity-less restart of the service by the OS, where {@code MainActivity}
 * never runs).
 */
final class HypeMediaStoreLifecycleListener implements FlutterForegroundTaskLifecycleListener {
    private static HypeMediaStoreLifecycleListener sInstance;

    private final Context appContext;
    @Nullable private MethodChannel channel;

    private HypeMediaStoreLifecycleListener(Context appContext) {
        this.appContext = appContext.getApplicationContext();
    }

    static synchronized HypeMediaStoreLifecycleListener getInstance(Context context) {
        if (sInstance == null) {
            sInstance = new HypeMediaStoreLifecycleListener(context);
        }
        return sInstance;
    }

    @Override
    public void onEngineCreate(@Nullable FlutterEngine flutterEngine) {
        if (flutterEngine == null) return;
        channel = HypeMediaStoreChannel.attach(
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
    }
}
