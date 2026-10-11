package x.a.zix;

import android.content.Context;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import android.util.Log;

import org.json.JSONObject;

import java.io.File;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

/**
 * Java side of the live stem engine (cpp/stems): the control surface the
 * Flutter channel talks to, plus track registration for the players.
 *
 * <p>The engine separates ahead of each playhead on its own native thread;
 * nothing here runs on an audio thread. Model loading and the speed test take
 * seconds, so they run on a background executor and answer on the main thread.
 */
public final class StemEngineBridge {
    private static final String TAG = "HypeStems";

    static {
        System.loadLibrary("eq_app");
    }

    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    // Model loading runs here, and ONNX Runtime's compute threads inherit this
    // thread's niceness: keep them below the UI (nice 4), but out of the
    // CPU-capped background group THREAD_PRIORITY_BACKGROUND would mean.
    private static final ExecutorService WORK = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(() -> {
            android.os.Process.setThreadPriority(4);
            r.run();
        }, "HypeStemsControl");
        return t;
    });
    private static final Map<String, Integer> TRACK_IDS = new ConcurrentHashMap<>();

    private static volatile Context appContext;
    private static volatile EventChannel.EventSink eventSink;
    private static boolean initialized;

    private StemEngineBridge() {}

    /** Idempotent. Call before any player is created. */
    public static synchronized void init(Context context) {
        appContext = context.getApplicationContext();
        if (initialized) return;
        File cache = new File(appContext.getCacheDir(), "stems");
        //noinspection ResultOfMethodCallIgnored
        cache.mkdirs();
        // Decoded audio from an earlier run is useless now.
        File[] stale = cache.listFiles();
        if (stale != null) for (File f : stale) //noinspection ResultOfMethodCallIgnored
            f.delete();
        nativeInit(cache.getAbsolutePath());
        initialized = true;
    }

    public static void setupEventChannel(EventChannel channel) {
        channel.setStreamHandler(new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object arguments, EventChannel.EventSink events) {
                eventSink = events;
                events.success(statusMap());
            }

            @Override
            public void onCancel(Object arguments) {
                eventSink = null;
            }
        });
    }

    // ---- Flutter channel ----------------------------------------------------

    public static void loadModel(String dir, MethodChannel.Result result) {
        WORK.execute(() -> {
            String error = nativeLoadModel(dir == null ? "" : dir);
            if (error != null) Log.w(TAG, "model load failed: " + error);
            MAIN.post(() -> result.success(error == null));
        });
    }

    public static void unloadModel() {
        WORK.execute(StemEngineBridge::nativeUnloadModel);
    }

    public static void benchmark(MethodChannel.Result result) {
        WORK.execute(() -> {
            Map<String, Object> map = jsonToMap(nativeBenchmark());
            MAIN.post(() -> result.success(map));
        });
    }

    public static void setArmed(boolean armed) {
        nativeSetArmed(armed);
    }

    public static void setLevels(float vocals, float drums, float instruments) {
        nativeSetLevels(vocals, drums, instruments);
    }

    /**
     * A local copy of a streamed track (the app downloads YouTube streams while
     * stems are in use): the engine decodes it for the player's stream URL.
     */
    public static void provideStream(String url, String path) {
        if (url == null || url.isEmpty() || path == null || path.isEmpty()) return;
        nativeProvideSource(url, path);
    }

    public static Map<String, Object> statusMap() {
        return jsonToMap(nativeStatusJson());
    }

    /** From the engine's worker thread. */
    @SuppressWarnings("unused")
    static void onNativeStatus(String json) {
        Map<String, Object> map = jsonToMap(json);
        MAIN.post(() -> {
            EventChannel.EventSink sink = eventSink;
            if (sink != null) sink.success(map);
        });
    }

    // ---- Players --------------------------------------------------------------

    /**
     * Interns a player's media URI with the engine and returns its id (0 for
     * none). Local files are keyed by their decoded path; streams by their URL,
     * which is how {@link #provideStream} finds them.
     */
    public static int registerTrack(String uriString) {
        if (uriString == null || uriString.isEmpty()) return 0;
        Integer known = TRACK_IDS.get(uriString);
        if (known != null) return known;

        Uri uri = Uri.parse(uriString);
        String scheme = uri.getScheme();
        String key = uriString;
        String path = null;
        int fd = -1;
        String reason = "";
        if (scheme == null || "file".equals(scheme)) {
            path = uri.getPath();
            if (path == null || path.isEmpty()) {
                reason = "unsupported";
            } else {
                key = path;
            }
        } else if ("content".equals(scheme)) {
            Context ctx = appContext;
            try {
                ParcelFileDescriptor pfd = ctx == null ? null : ctx.getContentResolver().openFileDescriptor(uri, "r");
                if (pfd == null) reason = "decode";
                else fd = pfd.detachFd();
            } catch (Exception e) {
                reason = "decode";
            }
        } else if ("http".equals(scheme) || "https".equals(scheme)) {
            reason = "stream";
        } else {
            reason = "unsupported";
        }
        int id = nativeRegisterTrack(key, path, fd, reason);
        TRACK_IDS.put(uriString, id);
        return id;
    }

    // ---- Helpers --------------------------------------------------------------

    private static Map<String, Object> jsonToMap(String json) {
        Map<String, Object> out = new HashMap<>();
        if (json == null) return out;
        try {
            JSONObject o = new JSONObject(json);
            Iterator<String> keys = o.keys();
            while (keys.hasNext()) {
                String k = keys.next();
                Object v = o.get(k);
                out.put(k, v == JSONObject.NULL ? null : v);
            }
        } catch (Exception e) {
            Log.w(TAG, "bad status json: " + json);
        }
        return out;
    }

    // ---- Native ---------------------------------------------------------------

    private static native void nativeInit(String cacheDir);
    private static native String nativeLoadModel(String dir);
    private static native void nativeUnloadModel();
    private static native String nativeBenchmark();
    private static native void nativeSetArmed(boolean armed);
    private static native void nativeSetLevels(float vocals, float drums, float instruments);
    private static native void nativeProvideSource(String key, String path);
    private static native int nativeRegisterTrack(String key, String path, int fd, String reason);
    private static native String nativeStatusJson();
}
