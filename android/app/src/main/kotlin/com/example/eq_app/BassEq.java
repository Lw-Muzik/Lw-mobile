package com.example.eq_app;

import android.media.audiofx.BassBoost;

public class BassEq {
    public static int m = Integer.MAX_VALUE;
    private static BassBoost bassBoost;

    public static void init(int sessionId) {
        bassBoost = new BassBoost(m, 0);
    }

    public static void enable(boolean enable) {
        if (bassBoost != null){
            bassBoost.setEnabled(enable);
        }
    }

    public static boolean isEnabled() {
        return bassBoost != null ? bassBoost.getEnabled():false;

    }

    public static void setStrength(int strength) {
        if (bassBoost != null){
            short s = ((short)strength);
            bassBoost.setStrength(s);
        }

    }

    public static short getStrength() {
        return (bassBoost != null) ? bassBoost.getRoundedStrength():0;
    }
}
