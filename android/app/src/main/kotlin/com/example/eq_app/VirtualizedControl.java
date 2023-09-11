package com.example.eq_app;

import android.media.audiofx.Virtualizer;

public class VirtualizerControl {
    private static Virtualizer virtualizer;
    private static final int m = Integer.MAX_VALUE;
    static void initVirtualizer(int sessionId) {
        virtualizer = new Virtualizer(m, sessionId);
    }

    public static void enable(boolean enable) {
        if (virtualizer != null) {
            virtualizer.setEnabled(enable);
        }
    }

//    public static boolean isEnabled() {
//        if (virtualizer != null) {
//            return virtualizer.getEnabled();
//        }
//        return false;
//    }

    public static void setStrength(int strength) {
        if (virtualizer != null)
            virtualizer.setStrength((short)strength);
    }

    public static int getStrength() {
        if (virtualizer != null){
            return virtualizer.getRoundedStrength();
        }
        return 0;
    }
}
