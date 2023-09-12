package com.example.eq_app;


import android.media.audiofx.Visualizer;
import android.os.Build;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {

  private static final String CHANNEL = "eq_app";
  private final AudioVisualizer visualizer =  AudioVisualizer.instance;
  private MethodChannel visualizerChannel; // Define the MethodChannel here
 
  @Override
  public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
  super.configureFlutterEngine(flutterEngine);
  visualizerChannel =  new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL);

     visualizerChannel.setMethodCallHandler(
          (call, result) -> {
            switch (call.method) {
                case "activate_visualizer":
                if (visualizer.isActive()) {
                    return;
                }
                int sessionID = call.argument("sessionID");
                    visualizer.activate(new Visualizer.OnDataCaptureListener() {
                        @Override
                        public void onWaveFormDataCapture(Visualizer visualizer, byte[] waveform, int samplingRate) {
                            Map<String, Object> args = new HashMap<>();
                            args.put("waveform", waveform);
                            args.put("sampleRate", samplingRate);

                            // Initialize the visualization frame rate controls
                            // Sleep for a second to slow down the rendering.
                            visualizerChannel.invokeMethod("onWaveformVisualization", args);
                        }

                        @Override
                        public void onFftDataCapture(Visualizer visualizer, byte[] sharedFft, int samplingRate) {
                            Map<String, Object> args = new HashMap<>();
                            args.put("fft", sharedFft);
                            visualizerChannel.invokeMethod("onFftVisualization", args);
                        }
                    }, sessionID);
                    break;

                case "enableVisual":
                    boolean enable = call.argument("enableVisual");
                    visualizer.enableVisual(enable);
                    break;

                case "getEnabled":
                    boolean eqEnabled = visualizer.isEnabled();
                    result.success(eqEnabled);
                    break;

                case "setScalingMode":
                    boolean scale = call.argument("scale");
                    visualizer.setScalingMode(scale);
                    break;

                case "setFrameRate":
                int frameRate = call.argument("frameRate");
                visualizer.setFrameRate(frameRate);
                break;

                case "init":
                    int sessionId = call.argument("sessionId");
                    CustomEq.init(sessionId);
                    break;
                    
                case "enableEq":
                    boolean enableEq = call.argument("enable");
                   CustomEq.enable(enableEq);
                    break;
                case "isEnabled":
                  boolean isEnabled =  CustomEq.isEnabled();
                  result.success(isEnabled);
                    break;
                case "getSettings":
                    String settings = CustomEq.getSettings();
                    result.success(settings);
                break;
                case "getBandLevel":
                    int _b = call.argument("_band");
                    short _bb = (short)_b;
                    int res = CustomEq.getBandLevel(_bb);
                    result.success(res);
                    break;
                case "setBandLevel":
                    int band = (int)call.argument("band");
                    int level = (int)call.argument("level");//(int)(1500f / 100f
                    CustomEq.setBandLevel(band,  (100 * level));
                    break;
                case "getBandLevelRange":
                    ArrayList<Integer> bandLevels = CustomEq.getBandLevelRange();
                    result.success(bandLevels);
                    break;
                case "setSettings":
                    int bands = call.argument("nBands");
                    CustomEq.setSettings(bands);
                    break;
        
                case "getBandFreq":
                    ArrayList<Integer> freq = CustomEq.getCenterBandFreqs();
                    result.success(freq);
                    break;
                case"getPresetNames":
                    ArrayList<String> preset = CustomEq.getPresetNames();
                    result.success(preset);
                    break;
                case "setPreset":
                    String presetName = call.argument("preset");
                    CustomEq.setPreset(presetName);
                    break;

//                        virtualizer
                case "initVirtualizer":
                        int sessionIdV = call.argument("sessionId");
                        VirtualizedControl.initVirtualizer(sessionIdV);
                    break;

                case "enableVirtualizer":
                     boolean enableV = call.argument("enable");
                     VirtualizedControl.enable(enableV);
                    break;
                case "getVirtualEnabled":
                  boolean virtualEnabled =  VirtualizedControl.getVirtualEnabled();
                  result.success(virtualEnabled);
                  break;

                case "virtualizerStrength":
                    int strength = VirtualizedControl.getStrength();
                    result.success(strength);
                    break;

                case "setVirtualizerStrength":
                        int strengthV = call.argument("strength");
                        VirtualizedControl.setStrength(strengthV);
                    break;
                case "forceVirtualization":
                    result.success(VirtualizedControl.forceVirtualizationEnabled());
                    break;

        //     bassboost
                case "initBassBoost":
                        int sessionIdB = call.argument("sessionId");
                        BassEq.init(sessionIdB);
                    break;

                case "enableBassBoost":
                            boolean enableB = call.argument("enableBass");
                            BassEq.enable(enableB);
                            break;
                case "isBassEnabled":
                    boolean isBassEnabled = BassEq.isEnabled();
                    result.success(isBassEnabled);
                    break;

                case "bassBoostStrength":
                        int strengthB = ((int)BassEq.getStrength());
                        result.success(strengthB);
                        break;
                case "setBassBoostStrength":
                        int strengthBB = call.argument("strength");
                        BassEq.setStrength(strengthBB);
                        break;


//                        loudnessEnhancer
                case "initLoudnessEnhancer":
                        int sessionIdL = call.argument("sessionId");
                        LoudnessControl.init(sessionIdL);
                        break;
                case "enableLoudnessEnhancer":
                            boolean enableL = call.argument("enableLoud");
                            LoudnessControl.enable(enableL);
                            break;
                case "loudnessEnhancerEnabled":
                    boolean enabled = LoudnessControl.isEnabled();
                   result.success(enabled);
                    break;
                case "loudnessEnhancerStrength":
                        float strengthL = LoudnessControl.getTargetGain();
                        result.success(strengthL);
                        break;
                case "setLoudnessEnhancerStrength":
                        int strengthLL = call.argument("strength");
                        LoudnessControl.setTargetGain(strengthLL);
                        break;
                
//                            reverb
                case "initReverb":
                        int sessionIdR = call.argument("sessionId");
                        ReverbControl.init(sessionIdR);
                        break;

                case "enableReverb":
                            boolean enableR = call.argument("enableReverb");
                            ReverbControl.enable(enableR);
                            break;
                case "isReverbEnabled":
                    boolean isReverbEnabled = ReverbControl.isEnabled();
                    result.success(isReverbEnabled);
                    break;
                
                case "setDecayTime":
                        int strengthRR = call.argument("decayTime");
                        ReverbControl.setDecayTime(strengthRR);
                        break;

                case "getDecayTime":
                           int decayTime =  ReverbControl.getDecayTime();
                           result.success(decayTime);
                        break;

                case "setDensity":
                    int density = call.argument("density");
                    ReverbControl.setDensity(density);
                    break;

                case "getDensity":
                    int gDensity = ReverbControl.getDensity();
                    result.success(gDensity);
                    break;

                case "setDiffusion":
                        int diffusion = call.argument("diffusion");
                        ReverbControl.setDiffusion(diffusion);
                    break;

                case "getDiffusion":
                        int getDiffusion = ReverbControl.getDiffusion();
                        result.success(getDiffusion);
                    break;

                case "setReflectionsDelay":
                        int reflectionsDelay = call.argument("reflectionsDelay");
                        ReverbControl.setReflectionsDelay(reflectionsDelay);
                    break;

                case "getReflectionsDelay":
                        int getReflectionsDelay = ReverbControl.getReflectionsDelay();
                        result.success(getReflectionsDelay);
                        break;

                case "setReflectionsLevel":
                        int reflectionsLevel = call.argument("reflectionsLevel");
                        ReverbControl.setReflectionsLevel(reflectionsLevel);
                        break;

                case "getReflectionsLevel":
                        int getReflectionsLevel = ReverbControl.getReflectionsLevel();
                        result.success(getReflectionsLevel);
                        break;

                case "setReverbDelay":
                        int reverbDelay = call.argument("reverbDelay");
                        ReverbControl.setReverbDelay(reverbDelay);
                        break;

                case "getReverbDelay":
                            int getReverbDelay = ReverbControl.getReverbDelay();
                            result.success(getReverbDelay);
                        break;

                case "setReverbLevel":
                                int reverbLevel = call.argument("reverbLevel");
                                ReverbControl.setReverbLevel(reverbLevel);
                        break;

                case "getReverbLevel":
                        int getReverbLevel = ReverbControl.getReverbLevel();
                        result.success(getReverbLevel);
                        break;

                    case "setRoomLevel":
                            int roomLevel = call.argument("roomLevel");
                             ReverbControl.setRoomLevel(roomLevel);
                            break;

                    case "getRoomLevel":
                                int getRoomLevel = ReverbControl.getRoomLevel();
                                result.success(getRoomLevel);
                                break;

                    case "setRoomHFLevel":
                            int roomHFLevel = (int)call.argument("roomHFLevel");
                            ReverbControl.setRoomHFLevel(roomHFLevel);
                            break;

                    case "getRoomHFLevel":
                            int getRoomHFLevel = ReverbControl.getRoomHFLevel();
                            result.success(getRoomHFLevel);
                            break;

                    case "setDecayHFRatio":
                        int decayHFRatio = call.argument("decayHFRatio");
                        ReverbControl.setDecayHFRatioLevel(decayHFRatio);
                        break;

                    case "getDecayHFRatio":
                            int getDecayHFRatio = ReverbControl.getDecayHFRatio();
                            result.success(getDecayHFRatio);
                            break;
        //    DSP configurations
                case "initDSPEngine":
                    int dspId = call.argument("dspId");
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        DSPEngine.setAudioSessionId(dspId);
                        DSPEngine.initDSPEngine();
                    }
                    break;
                case "setDSPSpeakers":
                    Map<String, Object> map = call.argument("spks");
                    ArrayList<Integer> speaker = (ArrayList<Integer>) map.get("speakers");
                    ArrayList<Double> l = (ArrayList<Double>) map.get("levels");
//                   speakers
                    int[] speakers = new int[10];
                    float[] levels = new float[10];
                    for (int x = 0; x < 10; x++) {
                        speakers[x] = speaker.get(x);
                        levels[x] = l.get(x).floatValue();
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        DSPEngine.setDspSpeakers(speakers, levels);
                    }
                    result.success(speaker);
                    break;

                case "enableDSP":
                    boolean dspEnable = call.argument("enableEngine");
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        DSPEngine.enableEngine(dspEnable);
                    }
                    break;

                case "setOutGain":
                    double limitGain = call.argument("outGain");
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        DSPEngine.setOutGain(((float)limitGain));
                    }
                    break;
                case "getVocalLevel":
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        float vocalLevel = DSPEngine.getVocalLevel();
                        result.success(vocalLevel);
                    }
                    break;
                case "getOutGain":
                    float lGain = 0;
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        lGain = DSPEngine.getGainValue();
                        result.success(lGain);
                        
                    }
                    result.success(lGain);
                    break;

                case "setDSPXBass":
                    double bassGain = call.argument("xBass");
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        DSPEngine.setDSPXBass((float)bassGain);
                    }
                    break;
                case "setExtraBass":
                    double xtraGain = call.argument("extraBass");
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        DSPEngine.setDSPx((float)xtraGain);
                    }
                    break;
                case "setDSPPowerBass":
                    double powerBass = call.argument("powerBass");
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        DSPEngine.setDSPPowerBass(((float)powerBass));
                    }
                    break;
                    
                case "setDSPXTreble":
                    double trebleGain = call.argument("trebleGain");
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        DSPEngine.setDSPTreble((float)trebleGain);
                    }
                    break;
                case "setDSPVolume":
                    double dspVolume = call.argument("dspVolume");
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        DSPEngine.setDSPVolume(((float)dspVolume));
                    }
                    break;
                case "enableTuner":
                    boolean enableTuner = call.argument("enableTuner");
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        DSPEngine.setTuner(enableTuner);
                    }
                    break;
                case "setTunerBass":
                    double tBass = call.argument("tunerBass");
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        DSPEngine.adjustTunerBass((float)tBass);
                    }
                    break;
                case"setCutOffFreq":
                    int tBasFreq = call.argument("tunerBassFreq");
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        DSPEngine.setCutOffFrequencyForTunerBass(tBasFreq);
                    }
                    break;
                case "disposeDSP":
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        DSPEngine.dispose();
                    }
                    break;
                case "initPresetReverb":
                    int audioId = call.argument("priorityId");
                    ReverbEngine.initPresetReverb(audioId);
                    break;
                case "enablePresetReverb":
                    boolean enablePreset = call.argument("enablePreset");
                   int check = ReverbEngine.enablePresetReverb(enablePreset);
                   result.success(check);
                    break;
                case "setReverbPreset":
                    int pPreset = (int)call.argument("preset");
                    ReverbEngine.setPreset(pPreset);
                    break;

                case "getReverbPreset":
                    short g = ReverbEngine.getPreset();
                    result.success(((short)g));
                    break;

                default:
                result.notImplemented();
                break;
            }
          }
        );
  }
}