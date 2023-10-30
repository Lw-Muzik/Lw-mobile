package x.a.zix;

import android.media.audiofx.LoudnessEnhancer;

public class LoudnessControl {
    private static LoudnessEnhancer loudnessEnhancer;

    public static void init(int sessionId) {
        loudnessEnhancer = new LoudnessEnhancer(0);
    }

    public static void enable(boolean enable) {
        if (loudnessEnhancer != null){
            if(enable){
                loudnessEnhancer.setEnabled(true);
            } else{
                loudnessEnhancer.setEnabled(false);
            }
        }
    }

    public static boolean isEnabled() {
        if (loudnessEnhancer != null)
            return loudnessEnhancer.getEnabled();
        return false;
    }

    public static void setTargetGain(int gain) {
        if (loudnessEnhancer != null)
            loudnessEnhancer.setTargetGain(gain);
    }

    public static float getTargetGain() {
        if (loudnessEnhancer != null)
            return loudnessEnhancer.getTargetGain();
        return 0;
    }

}
