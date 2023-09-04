package com.example.eq_app;

import android.media.audiofx.Virtualizer;

public class VirtualizerControl {
    private static Virtualizer virtualizer;

    public static void init(int sessionId) {
        virtualizer = new Virtualizer(0, sessionId);
    }

    public static void enable(boolean enable) {
        if (virtualizer != null)
            virtualizer.setEnabled(enable);
    }

    public static boolean isEnabled() {
        if (virtualizer != null)
            return virtualizer.getEnabled();
        return false;
    }

    public static void setStrength(int strength) {
        if (virtualizer != null)
            virtualizer.setStrength((short)strength);
    }

    public static int getStrength() {
        if (virtualizer != null)
            return (int)virtualizer.getRoundedStrength();
        return 0;
    }
}
