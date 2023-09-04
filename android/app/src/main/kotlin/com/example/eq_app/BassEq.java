package com.example.eq_app;

import android.media.audiofx.BassBoost;

public class BassEq {
    private static BassBoost bassBoost;

    public static void init(int sessionId) {
        bassBoost = new BassBoost(0, sessionId);
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
