package x.a.zix;

import android.media.AudioManager;
import android.media.audiofx.PresetReverb;
import android.util.Log;

public class ReverbEngine {
    private static PresetReverb reverb;
    private static String TAG = "ReverbEngine";

    public static void initPresetReverb(int sessionId){
        if(reverb == null){
            try{
                reverb = new PresetReverb(Integer.MAX_VALUE, AudioManager.AUDIO_SESSION_ID_GENERATE);
            }catch (Exception ex){
                ex.printStackTrace();
            }
        }
    }
    public static int enablePresetReverb(boolean enable){
        if(reverb != null){
        initPresetReverb(AudioManager.AUDIO_SESSION_ID_GENERATE);
          return reverb.setEnabled(enable);
        }
        return -1;
    }
    public static void setPreset(int preset){
        if(reverb != null){
            initPresetReverb(AudioManager.AUDIO_SESSION_ID_GENERATE);
            try{
                ;
                switch((short) preset){
                    case PresetReverb.PRESET_SMALLROOM:
                        reverb.setPreset(PresetReverb.PRESET_SMALLROOM);
                        Log.d(TAG, "setPreset: small room");
                        break;

                    case PresetReverb.PRESET_LARGEHALL:
                        reverb.setPreset(PresetReverb.PRESET_LARGEHALL);
                        Log.d(TAG, "setPreset: large hall");
                        break;

                        case PresetReverb.PRESET_LARGEROOM:
                        reverb.setPreset(PresetReverb.PRESET_LARGEROOM);
                        Log.d(TAG, "setPreset: large room");
                        break;

                    case PresetReverb.PRESET_MEDIUMROOM:
                        reverb.setPreset(PresetReverb.PRESET_MEDIUMROOM);
                        Log.d(TAG, "setPreset: medium room");
                        break;

                    case PresetReverb.PRESET_MEDIUMHALL:
                        reverb.setPreset(PresetReverb.PRESET_MEDIUMHALL);
                        Log.d(TAG, "setPreset: medium hall");
                        break;

                    case PresetReverb.PRESET_PLATE:
                        reverb.setPreset(PresetReverb.PRESET_PLATE);
                        Log.d(TAG, "setPreset: plate");
                        break;
                        
                    default:
                        reverb.setPreset(PresetReverb.PRESET_NONE);
                        Log.d(TAG, "setPreset: none");
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

