package x.a.zix;

import android.media.audiofx.BassBoost;

public class BassEq {
     static final int m = Integer.MAX_VALUE;
    private static BassBoost bassBoost;

    public static void init(int sessionId) {
        bassBoost = new BassBoost(m, sessionId);
    }

    public static void enable(boolean enable) {
        if (bassBoost != null){
            bassBoost.setEnabled(enable);
        }
    }

    public static boolean isEnabled() {
        return bassBoost != null && bassBoost.getEnabled();

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
