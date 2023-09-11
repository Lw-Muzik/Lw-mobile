package com.example.eq_app;

import android.media.audiofx.Virtualizer;

public class VirtualizedControl {
    private static Virtualizer virtualizer;
    private static final int m = Integer.MAX_VALUE;
    static void initVirtualizer(int sessionId) {
        if(virtualizer == null){
            virtualizer = new Virtualizer(m, sessionId);
        }
    }

    public static void enable(boolean enable) {
        if (virtualizer != null) {
            virtualizer.setEnabled(enable);
//            virtualizer.forceVirtualizationMode(Virtualizer.VIRTUALIZATION_MODE_BINAURAL); // VIRTUALIZATION_MODE_TRANSAURAL => 3, VIRTUALIZATION_MODE_BINAURAL => 2
        }
    }
    public static boolean getVirtualEnabled(){
        if(virtualizer != null){
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
