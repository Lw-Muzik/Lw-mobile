package x.a.zix;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/**
 * Brings Hype Connect back after a reboot or an app update, if the user had it
 * on. Boot and package-replaced broadcasts are among the few moments Android
 * 12+ lets an app start a foreground service from the background.
 *
 * <p>The "had it on" flag is mirrored into native preferences by Dart whenever
 * it changes (see {@code ConnectServiceController}); this receiver never
 * reads Flutter's shared_preferences file.
 */
public class ConnectBootReceiver extends BroadcastReceiver {
    private static final String TAG = "ConnectBootReceiver";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent == null ? null : intent.getAction();
        if (!Intent.ACTION_BOOT_COMPLETED.equals(action)
                && !Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)) {
            return;
        }
        if (!ConnectService.isWanted(context)) return;
        Log.i(TAG, "restoring Hype Connect after " + action);
        ConnectService.start(context);
    }
}
