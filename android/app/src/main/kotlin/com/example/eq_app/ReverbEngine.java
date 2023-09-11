package com.example.eq_app;

import android.media.audiofx.PresetReverb;

public class ReverbEngine {
    private static PresetReverb reverb;

    public static void initPresetReverb(int sessionId){
        if(reverb == null){
            try{
                reverb = new PresetReverb(Integer.MAX_VALUE, sessionId);
            }catch (Exception ex){
                ex.printStackTrace();
            }
        }
    }
    public static int enablePresetReverb(boolean enable){
        if(reverb != null){
          return  reverb.setEnabled(enable);
        }
        return -1;
    }
    public static void setPreset(int preset){
        if(reverb != null){
            try{
                switch(preset){
                    case PresetReverb.PRESET_SMALLROOM:
                        reverb.setPreset(PresetReverb.PRESET_SMALLROOM);
                        break;
                    case PresetReverb.PRESET_LARGEHALL:
                        reverb.setPreset(PresetReverb.PRESET_LARGEHALL);
                        break;
                        case PresetReverb.PRESET_LARGEROOM:
                        reverb.setPreset(PresetReverb.PRESET_LARGEROOM);
                        break;
                    case PresetReverb.PRESET_MEDIUMROOM:
                        reverb.setPreset(PresetReverb.PRESET_MEDIUMROOM);
                        break;
                    case PresetReverb.PRESET_MEDIUMHALL:
                        reverb.setPreset(PresetReverb.PRESET_MEDIUMHALL);
                        break;
                    case PresetReverb.PRESET_PLATE:
                        reverb.setPreset(PresetReverb.PRESET_PLATE);
                        break;
                    default:
                        reverb.setPreset(PresetReverb.PRESET_NONE);
                        break;
                }
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

