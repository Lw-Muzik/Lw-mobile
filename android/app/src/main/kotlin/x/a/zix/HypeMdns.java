package x.a.zix;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.net.wifi.WifiManager;
import android.util.Log;

import java.util.Map;

/**
 * Process-level mDNS (DNS-SD) advertiser + Wi-Fi multicast lock for Phone Link.
 *
 * <p>{@link NsdManager#registerService} talks to the system mDNS daemon directly,
 * so it is independent of which {@code FlutterEngine}/isolate calls it — unlike
 * the bonsoir plugin, whose platform channel is bound to the (secondary)
 * foreground-service engine where its advertisement previously went silent.
 * Holding a {@link WifiManager.MulticastLock} keeps inbound mDNS queries flowing
 * while the phone is idle/backgrounded.
 *
 * <p>All methods are safe to call repeatedly; {@link #register} withdraws any
 * previous registration first. State is process-static so it survives the app
 * being swiped from recents (the foreground service keeps the process alive).
 */
final class HypeMdns {
    private static final String TAG = "HypeMdns";
    private static final String LOCK_TAG = "hype-mdns-lock";

    private static final Object LOCK = new Object();
    private static NsdManager sNsdManager;
    private static NsdManager.RegistrationListener sListener;
    private static WifiManager.MulticastLock sMulticastLock;

    private HypeMdns() {}

    static void register(Context context, String name, String type, int port, Map<String, String> txt) {
        final Context app = context.getApplicationContext();
        synchronized (LOCK) {
            // Withdraw any previous registration so a re-register (new port/txt)
            // starts clean. NsdManager rejects reusing a RegistrationListener, so
            // we always build a fresh one below.
            unregisterLocked();

            final NsdManager nsd = nsdManager(app);
            if (nsd == null) {
                Log.w(TAG, "NSD service unavailable");
                return;
            }

            final NsdServiceInfo info = new NsdServiceInfo();
            info.setServiceName(name);
            info.setServiceType(type);
            info.setPort(port);
            if (txt != null) {
                for (Map.Entry<String, String> e : txt.entrySet()) {
                    if (e.getKey() == null) continue;
                    info.setAttribute(e.getKey(), e.getValue() == null ? "" : e.getValue());
                }
            }

            final NsdManager.RegistrationListener listener = new NsdManager.RegistrationListener() {
                @Override public void onServiceRegistered(NsdServiceInfo info) {
                    Log.i(TAG, "registered as " + info.getServiceName());
                }
                @Override public void onRegistrationFailed(NsdServiceInfo info, int errorCode) {
                    Log.w(TAG, "registration failed: " + errorCode);
                }
                @Override public void onServiceUnregistered(NsdServiceInfo info) {
                    Log.i(TAG, "unregistered");
                }
                @Override public void onUnregistrationFailed(NsdServiceInfo info, int errorCode) {
                    Log.w(TAG, "unregistration failed: " + errorCode);
                }
            };

            try {
                nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener);
                sListener = listener;
            } catch (Exception e) {
                Log.e(TAG, "registerService threw", e);
                sListener = null;
            }
        }
    }

    static void unregister() {
        synchronized (LOCK) {
            unregisterLocked();
        }
    }

    private static void unregisterLocked() {
        if (sNsdManager != null && sListener != null) {
            try {
                sNsdManager.unregisterService(sListener);
            } catch (Exception e) {
                // e.g. IllegalArgumentException if it was never fully registered.
                Log.w(TAG, "unregisterService threw", e);
            }
        }
        sListener = null;
    }

    static void acquireMulticastLock(Context context) {
        final Context app = context.getApplicationContext();
        synchronized (LOCK) {
            if (sMulticastLock != null && sMulticastLock.isHeld()) return;
            try {
                final WifiManager wifi =
                        (WifiManager) app.getSystemService(Context.WIFI_SERVICE);
                if (wifi == null) {
                    Log.w(TAG, "WifiManager unavailable");
                    return;
                }
                final WifiManager.MulticastLock lock = wifi.createMulticastLock(LOCK_TAG);
                lock.setReferenceCounted(false);
                lock.acquire();
                sMulticastLock = lock;
            } catch (Exception e) {
                // Requires CHANGE_WIFI_MULTICAST_STATE; log rather than crash.
                Log.e(TAG, "acquireMulticastLock threw", e);
            }
        }
    }

    static void releaseMulticastLock() {
        synchronized (LOCK) {
            if (sMulticastLock != null) {
                try {
                    if (sMulticastLock.isHeld()) sMulticastLock.release();
                } catch (Exception e) {
                    Log.w(TAG, "releaseMulticastLock threw", e);
                }
                sMulticastLock = null;
            }
        }
    }

    private static NsdManager nsdManager(Context app) {
        if (sNsdManager == null) {
            sNsdManager = (NsdManager) app.getSystemService(Context.NSD_SERVICE);
        }
        return sNsdManager;
    }
}
