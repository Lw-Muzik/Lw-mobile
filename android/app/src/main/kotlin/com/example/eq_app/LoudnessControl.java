package com.example.eq_app;

import android.media.audiofx.LoudnessEnhancer;

public class LoudnessControl {
    private static LoudnessEnhancer loudnessEnhancer;

    public static void init(int sessionId) {
        loudnessEnhancer = new LoudnessEnhancer(sessionId);
    }

    public static void enable(boolean enable) {
        if (loudnessEnhancer != null){
            if(enable == true){
                loudnessEnhancer.setEnabled(enable);
            } else{
                loudnessEnhancer.setEnabled(enable);
                // loudnessEnhancer.release();
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
