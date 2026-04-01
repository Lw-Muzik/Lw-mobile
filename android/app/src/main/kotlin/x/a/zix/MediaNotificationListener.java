package x.a.zix;

import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;

/**
 * Minimal NotificationListenerService required for MediaSessionManager.getActiveSessions()
 * to return sessions from ALL apps (not just our own).
 *
 * The user must grant "Notification access" in Settings for this to work.
 * Without it, MediaSessionManager falls back to returning only our sessions,
 * and we rely on AudioPlaybackConfiguration (API 34+) or reflection (API 28-33).
 *
 * This service does NOT read or process any notifications.
 */
public class MediaNotificationListener extends NotificationListenerService {

    @Override
    public void onNotificationPosted(StatusBarNotification sbn) {
        // Not used — we only need this service for MediaSessionManager access
    }

    @Override
    public void onNotificationRemoved(StatusBarNotification sbn) {
        // Not used
    }
}
