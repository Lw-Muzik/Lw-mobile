package com.example.eq_app;

import android.media.audiofx.PresetReverb;

public class ReverbEngine {
    private static PresetReverb reverb;

    public static void initPresetReverb(int sessionId){
        if(reverb == null){
            try{
                reverb = new PresetReverb(Integer.MAX_VALUE, 0);
            }catch (Exception ex){
                ex.printStackTrace();
            }
        }
    }
    public static void enablePresetReverb(boolean enable){
        if(reverb != null){
            reverb.setEnabled(enable);
        }
    }
    public static void setPreset(short preset){
        if(reverb != null){
            try{
                reverb.setPreset(preset);
            } catch (Exception ex){
                ex.printStackTrace();
            }
        }

    }
    public static short getPreset(){
        if(reverb != null) {
            try {
                return reverb.getPreset();
            } catch (Exception ex) {
                ex.printStackTrace();
            }
        }
        return 0;
    }
}

