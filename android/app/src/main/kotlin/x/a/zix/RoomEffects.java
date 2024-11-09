
package x.a.zix;
// import android.media.AudioManager;
// import android.media.audiofx.EnvironmentalReverb;
// import android.media.audiofx.PresetReverb;
// import android.os.Build;

// public class RoomEffects {
//     private EnvironmentalReverb environmentalReverb;
//     private PresetReverb presetReverb;
//     private int priority = 0;
//     private int audioSession;

//     // Room presets constants
//     public static final int PRESET_NONE = 0;
//     public static final int PRESET_SMALL_ROOM = 1;
//     public static final int PRESET_MEDIUM_ROOM = 2;
//     public static final int PRESET_LARGE_ROOM = 3;
//     public static final int PRESET_MEDIUM_HALL = 4;
//     public static final int PRESET_LARGE_HALL = 5;
//     public static final int PRESET_PLATE = 6;
//     public static final int PRESET_SCENE = 7;
//     public static final int PRESET_CONCERT = 8;
//     public static final int PRESET_ARENA = 9;
//     public static final int m = Integer.MAX_VALUE;

//     public RoomEffects(int audioSession) {
//         this.audioSession = AudioManager.AUDIO_SESSION_ID_GENERATE; // Generate a new session
//         initializeEffects();
//     }

//     private void initializeEffects() {
//         try {
//             if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
//                 // Android 14+ implementation
//                 environmentalReverb = new EnvironmentalReverb(m,audioSession)
//                     .setTargetVersions(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
//                     .build();
//             } else {
//                 // Legacy implementation
//                 environmentalReverb = new EnvironmentalReverb(priority, audioSession);
//             }
//             presetReverb = new PresetReverb(priority, audioSession);
//         } catch (Exception e) {
//             e.printStackTrace();
//         }
//     }

//     public void applyRoomEffect(int preset) {
//         if (environmentalReverb == null || presetReverb == null) return;

//         switch (preset) {
//             case PRESET_NONE:
//                 setEnvironmentalParameters(0, 0, 0, 0, 0, 0);
//                 break;
//             case PRESET_SMALL_ROOM:
//                 setEnvironmentalParameters(1000, -1000, 20, 500, 1000, 500);
//                 break;
//             case PRESET_MEDIUM_ROOM:
//                 setEnvironmentalParameters(2000, -900, 0, 1000, 2000, 1000);
//                 break;
//             case PRESET_LARGE_ROOM:
//                 setEnvironmentalParameters(3000, -800, -20, 1500, 3000, 1500);
//                 break;
//             case PRESET_MEDIUM_HALL:
//                 setEnvironmentalParameters(4000, -700, -30, 2000, 4000, 2000);
//                 break;
//             case PRESET_LARGE_HALL:
//                 setEnvironmentalParameters(5000, -600, -40, 3000, 5000, 3000);
//                 break;
//             case PRESET_PLATE:
//                 setEnvironmentalParameters(1500, -1200, 0, 750, 1500, 750);
//                 break;
//             case PRESET_SCENE:
//                 setEnvironmentalParameters(3500, -500, -15, 1750, 3500, 1750);
//                 break;
//             case PRESET_CONCERT:
//                 setEnvironmentalParameters(6000, -500, -50, 4000, 6000, 4000);
//                 break;
//             case PRESET_ARENA:
//                 setEnvironmentalParameters(7000, -400, -60, 5000, 7000, 5000);
//                 break;
//         }

//         // Also set preset reverb for compatible devices
//         try {
//             presetReverb.setPreset(getPresetReverbSetting(preset));
//         } catch (Exception e) {
//             e.printStackTrace();
//         }
//     }

//     private void setEnvironmentalParameters(
//             int decayTime,
//             int roomLevel,
//             int reflectionsLevel,
//             int reflectionsDelay,
//             int reverbLevel,
//             int reverbDelay) {
//         try {
//             environmentalReverb.setDecayTime(decayTime);
//             environmentalReverb.setRoomLevel((short) roomLevel);
//             environmentalReverb.setReflectionsLevel((short) reflectionsLevel);
//             environmentalReverb.setReflectionsDelay(reflectionsDelay);
//             environmentalReverb.setReverbLevel((short) reverbLevel);
//             environmentalReverb.setReverbDelay(reverbDelay);
//             environmentalReverb.setDiffusion((short) 1000); // High diffusion for realistic sound
//             environmentalReverb.setDensity((short) 1000);   // High density for rich sound
//         } catch (Exception e) {
//             e.printStackTrace();
//         }
//     }

//     private short getPresetReverbSetting(int preset) {
//         switch (preset) {
//             case PRESET_NONE:
//                 return PresetReverb.PRESET_NONE;
//             case PRESET_SMALL_ROOM:
//                 return PresetReverb.PRESET_SMALLROOM;
//             case PRESET_MEDIUM_ROOM:
//                 return PresetReverb.PRESET_MEDIUMROOM;
//             case PRESET_LARGE_ROOM:
//                 return PresetReverb.PRESET_LARGEROOM;
//             case PRESET_MEDIUM_HALL:
//                 return PresetReverb.PRESET_MEDIUMHALL;
//             case PRESET_LARGE_HALL:
//                 return PresetReverb.PRESET_LARGEHALL;
//             case PRESET_PLATE:
//                 return PresetReverb.PRESET_PLATE;
//             default:
//                 return PresetReverb.PRESET_NONE;
//         }
//     }

//     public void enableEffect(boolean enable) {
//         try {
//             if (environmentalReverb != null) {
//                 environmentalReverb.setEnabled(enable);
//             }
//             if (presetReverb != null) {
//                 presetReverb.setEnabled(enable);
//             }
//         } catch (Exception e) {
//             e.printStackTrace();
//         }
//     }

//     public void release() {
//         try {
//             if (environmentalReverb != null) {
//                 environmentalReverb.release();
//                 environmentalReverb = null;
//             }
//             if (presetReverb != null) {
//                 presetReverb.release();
//                 presetReverb = null;
//             }
//         } catch (Exception e) {
//             e.printStackTrace();
//         }
//     }

//     // Helper method to get current Android version compatibility
//     public static boolean isAndroid14OrHigher() {
//         return Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE;
//     }
// }