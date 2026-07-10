package x.a.zix;

import android.content.Context;

import androidx.annotation.NonNull;

import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * MethodChannel bridge ({@code x.a.zix/mdns}) routing Dart calls to
 * {@link HypeMdns}. Attached to whichever {@code FlutterEngine} hosts the
 * sharing server — on Android that's the flutter_foreground_task background
 * engine (see {@link HypeMdnsLifecycleListener}).
 */
final class HypeMdnsChannel implements MethodChannel.MethodCallHandler {
    static final String CHANNEL = "x.a.zix/mdns";

    private final Context appContext;

    private HypeMdnsChannel(Context appContext) {
        this.appContext = appContext.getApplicationContext();
    }

    /** Create the channel on {@code messenger} and wire it to {@link HypeMdns}. */
    static MethodChannel attach(BinaryMessenger messenger, Context appContext) {
        final MethodChannel channel = new MethodChannel(messenger, CHANNEL);
        channel.setMethodCallHandler(new HypeMdnsChannel(appContext));
        return channel;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "registerService": {
                    final String name = call.argument("name");
                    final String type = call.argument("type");
                    final Integer port = call.argument("port");
                    if (name == null || type == null || port == null) {
                        result.error("bad_args", "name/type/port are required", null);
                        return;
                    }
                    HypeMdns.register(appContext, name, type, port, coerceTxt(call.argument("txt")));
                    result.success(null);
                    break;
                }
                case "unregisterService":
                    HypeMdns.unregister();
                    result.success(null);
                    break;
                case "acquireMulticastLock":
                    HypeMdns.acquireMulticastLock(appContext);
                    result.success(null);
                    break;
                case "releaseMulticastLock":
                    HypeMdns.releaseMulticastLock();
                    result.success(null);
                    break;
                default:
                    result.notImplemented();
            }
        } catch (Exception e) {
            result.error("mdns_error", e.getMessage(), null);
        }
    }

    /** Normalise the decoded TXT map to {@code Map<String,String>} defensively. */
    private static Map<String, String> coerceTxt(Map<String, Object> raw) {
        final Map<String, String> txt = new HashMap<>();
        if (raw != null) {
            for (Map.Entry<String, Object> e : raw.entrySet()) {
                if (e.getKey() == null) continue;
                txt.put(e.getKey(), e.getValue() == null ? "" : String.valueOf(e.getValue()));
            }
        }
        return txt;
    }
}
