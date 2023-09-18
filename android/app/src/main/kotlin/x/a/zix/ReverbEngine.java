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
          return  reverb.setEnabled(enable);
        }
        return -1;
    }
    public static void setPreset(int preset){
        if(reverb != null){
            try{
                ;
                switch((short) preset){
                    case PresetReverb.PRESET_SMALLROOM:
                        Log.d(TAG, "setPreset: small room");
                        reverb.setPreset(PresetReverb.PRESET_SMALLROOM);
                        break;
                    case PresetReverb.PRESET_LARGEHALL:
                        Log.d(TAG, "setPreset: large hall");
                        reverb.setPreset(PresetReverb.PRESET_LARGEHALL);
                        break;
                        case PresetReverb.PRESET_LARGEROOM:
                        Log.d(TAG, "setPreset: large room");
                        reverb.setPreset(PresetReverb.PRESET_LARGEROOM);
                        break;
                    case PresetReverb.PRESET_MEDIUMROOM:
                        Log.d(TAG, "setPreset: medium room");
                        reverb.setPreset(PresetReverb.PRESET_MEDIUMROOM);
                        break;
                    case PresetReverb.PRESET_MEDIUMHALL:
                        Log.d(TAG, "setPreset: medium hall");
                        reverb.setPreset(PresetReverb.PRESET_MEDIUMHALL);
                        break;
                    case PresetReverb.PRESET_PLATE:
                        Log.d(TAG, "setPreset: plate");
                        reverb.setPreset(PresetReverb.PRESET_PLATE);
                        break;
                    default:
                        Log.d(TAG, "setPreset: none");
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

