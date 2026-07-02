package x.a.zix;

import android.media.audiofx.BassBoost;

public class BassEq {
     static final int m = Integer.MAX_VALUE;
    private static BassBoost bassBoost;

    public static void init(int sessionId) {
        // Release any previous BassBoost before replacing it, otherwise the old
        // native AudioEffect leaks (and stays attached to its session).
        if (bassBoost != null) {
            try { bassBoost.release(); } catch (Exception ignored) {}
        }
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
