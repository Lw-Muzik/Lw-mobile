package x.a.zix;

import android.media.audiofx.Virtualizer;

public class VirtualizedControl {
    private static Virtualizer virtualizer;
    private static int boundSessionId = 0;
    private static int currentMode = Virtualizer.VIRTUALIZATION_MODE_TRANSAURAL; // 3
    private static final int PRIORITY = Integer.MAX_VALUE;

    static void initVirtualizer(int sessionId) {
        if (virtualizer != null && boundSessionId == sessionId) return;
        try {
            boolean wasEnabled = false;
            short savedStrength = 0;
            if (virtualizer != null) {
                wasEnabled = virtualizer.getEnabled();
                savedStrength = virtualizer.getRoundedStrength();
                virtualizer.release();
                virtualizer = null;
            }
            virtualizer = new Virtualizer(PRIORITY, sessionId);
            boundSessionId = sessionId;
            if (wasEnabled) {
                virtualizer.setEnabled(true);
                virtualizer.setStrength(savedStrength);
                virtualizer.forceVirtualizationMode(currentMode);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public static void enable(boolean enable) {
        if (virtualizer != null) {
            virtualizer.setEnabled(enable);
            if (enable) {
                virtualizer.forceVirtualizationMode(currentMode);
            }
        }
    }

    public static boolean getVirtualEnabled() {
        if (virtualizer != null) {
            return virtualizer.getEnabled();
        }
        return false;
    }

    public static int forceVirtualizationEnabled() {
        if (virtualizer != null) {
            return virtualizer.getVirtualizationMode();
        }
        return 0;
    }

    public static void setMode(int mode) {
        currentMode = mode;
        if (virtualizer != null && virtualizer.getEnabled()) {
            virtualizer.forceVirtualizationMode(mode);
        }
    }

    public static int getMode() {
        return currentMode;
    }

    public static void setStrength(int strength) {
        if (virtualizer != null)
            virtualizer.setStrength((short) strength);
    }

    public static int getStrength() {
        if (virtualizer != null) {
            return virtualizer.getRoundedStrength();
        }
        return 0;
    }

    public static void release() {
        if (virtualizer != null) {
            virtualizer.release();
            virtualizer = null;
            boundSessionId = 0;
        }
    }
}
