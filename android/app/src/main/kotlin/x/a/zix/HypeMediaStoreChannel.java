package x.a.zix;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * MethodChannel bridge ({@code x.a.zix/media_store}) routing Dart calls to
 * {@link MediaImporter}. Attached to whichever {@code FlutterEngine} hosts the
 * sharing server — on Android that's the flutter_foreground_task background
 * engine (see {@link HypeMediaStoreLifecycleListener}), which is where the
 * {@code POST /upload} endpoint runs; the {@code eq_app} channel on
 * {@code MainActivity} is bound to a different engine and is unreachable from
 * there.
 */
final class HypeMediaStoreChannel implements MethodChannel.MethodCallHandler {
    static final String CHANNEL = "x.a.zix/media_store";

    private final Context appContext;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private HypeMediaStoreChannel(Context appContext) {
        this.appContext = appContext.getApplicationContext();
    }

    /** Create the channel on {@code messenger} and wire it to {@link MediaImporter}. */
    static MethodChannel attach(BinaryMessenger messenger, Context appContext) {
        final MethodChannel channel = new MethodChannel(messenger, CHANNEL);
        channel.setMethodCallHandler(new HypeMediaStoreChannel(appContext));
        return channel;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (!"importAudio".equals(call.method)) {
            result.notImplemented();
            return;
        }
        final String sourcePath = call.argument("sourcePath");
        final String displayName = call.argument("displayName");
        final String mimeType = call.argument("mimeType");
        if (sourcePath == null || displayName == null || mimeType == null) {
            result.error("bad_args", "sourcePath/displayName/mimeType are required", null);
            return;
        }
        // Copying a whole track through the ContentResolver would hold the
        // platform thread long enough to ANR, so import on a worker and reply
        // from the main thread (MethodChannel.Result must be answered there).
        new Thread(() -> {
            Map<String, Object> imported = null;
            String failure = null;
            try {
                imported = MediaImporter.importAudio(
                        appContext, sourcePath, displayName, mimeType);
            } catch (Exception e) {
                failure = e.getMessage();
            }
            final Map<String, Object> value = imported;
            final String error = failure;
            mainHandler.post(() -> {
                if (error != null) {
                    result.error("media_store_error", error, null);
                } else {
                    result.success(value);
                }
            });
        }, "hype-media-import").start();
    }
}
