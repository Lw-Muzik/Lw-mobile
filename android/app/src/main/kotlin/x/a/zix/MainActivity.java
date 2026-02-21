package x.a.zix;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.media.AudioManager;
import android.media.audiofx.Visualizer;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.MediaStore;
import android.view.KeyEvent;
import android.widget.Toast;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.IntentSenderRequest;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.NonNull;
import androidx.activity.EdgeToEdge;

import com.ryanheise.audioservice.AudioServiceFragmentActivity;

import java.io.File;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends AudioServiceFragmentActivity {
    // static {
    // System.loadLibrary("eq_app");
    // }

    private static final String CHANNEL = "eq_app";
    private final AudioVisualizer visualizer = AudioVisualizer.getInstance();
    private MethodChannel visualizerChannel; // Define the MethodChannel here
    private ProjectMRenderer projectMRenderer;

    // Scoped-storage lyrics write state
    private ActivityResultLauncher<IntentSenderRequest> writeRequestLauncher;
    private MethodChannel.Result pendingWriteResult;
    private Uri pendingWriteUri;
    private File pendingModifiedFile;

    @Override
    protected void onCreate(Bundle savedInstance) {
        EdgeToEdge.enable(this);
        super.onCreate(savedInstance);
        new HeadphoneService();
        // Initialize AudioProcessor singletons so just_audio can discover them
        RoomEffectsProcessor.getInstance();
        VisualizerTapProcessor.getInstance();

        // Register launcher for MediaStore write-permission dialog (Android 11+)
        writeRequestLauncher = registerForActivityResult(
                new ActivityResultContracts.StartIntentSenderForResult(),
                activityResult -> {
                    if (pendingWriteResult == null) return;
                    boolean ok = false;
                    if (activityResult.getResultCode() == Activity.RESULT_OK
                            && pendingModifiedFile != null && pendingWriteUri != null) {
                        ok = LyricsManager.writeToUri(
                                getContentResolver(), pendingWriteUri, pendingModifiedFile);
                    }
                    if (pendingModifiedFile != null) pendingModifiedFile.delete();
                    pendingWriteResult.success(ok);
                    pendingWriteResult = null;
                    pendingWriteUri = null;
                    pendingModifiedFile = null;
                }
        );
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            if (DvcController.onVolumeButton("up")) return true;
        } else if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            if (DvcController.onVolumeButton("down")) return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @SuppressLint("NewApi")
    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        // DVC init & EventChannel
        DvcController.init(this);
        EventChannel dvcEventChannel = new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(), "eq_app/dvc_volume_button");
        DvcController.setupEventChannel(dvcEventChannel);

        // projectM renderer init
        projectMRenderer = new ProjectMRenderer(this, flutterEngine.getRenderer());

        visualizerChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        visualizerChannel.setMethodCallHandler(
                (call, result) -> {
                    switch (call.method) {
                        case "activate_visualizer":
                            if (visualizer.isActive()) {
                                return;
                            }
                            visualizer.activate(new Visualizer.OnDataCaptureListener() {
                                @SuppressLint("NewApi")
                                @Override
                                public void onWaveFormDataCapture(Visualizer visualizer, byte[] waveform,
                                        int samplingRate) {
                                    Map<String, Object> args = new HashMap<>();
                                    args.put("waveform", waveform);
                                    args.put("sampleRate", samplingRate);

                                    // Initialize the visualization frame rate controls
                                    // Sleep for a second to slow down the rendering.
                                    visualizerChannel.invokeMethod("onWaveformVisualization", args);
                                }

                                @Override
                                public void onFftDataCapture(Visualizer visualizer, byte[] sharedFft,
                                        int samplingRate) {
                                    Map<String, Object> args = new HashMap<>();
                                    args.put("fft", sharedFft);
                                    visualizerChannel.invokeMethod("onFftVisualization", args);
                                }
                            });
                            break;

                        case "enableVisual":
                            boolean enable = Boolean.TRUE.equals(call.argument("enableVisual"));
                            visualizer.enableVisual(enable);
                            break;

                        case "getEnabled":
                            boolean eqEnabled = visualizer.isEnabled();
                            result.success(eqEnabled);
                            break;

                        case "setScalingMode":
                            boolean scale = Boolean.TRUE.equals(call.argument("scale"));
                            visualizer.setScalingMode(scale);
                            break;

                        case "setFrameRate":
                            int frameRate = call.argument("frameRate");
                            // visualizer.(frameRate);
                            break;

                        case "init":
                            // Legacy CustomEq init — now routes to DSPEngine
                            int sessionId = call.argument("sessionId");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                DSPEngine.setAudioSessionId(sessionId);
                                DSPEngine.initDSPEngine();
                            }
                            break;

                        case "enableEq":
                            boolean enableEq = call.argument("enable");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                DSPEngine.enableEngine(enableEq);
                            }
                            break;
                        case "isEnabled":
                            boolean isEnabled = false;
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                isEnabled = DSPEngine.isDynamicsProcessingAvailable();
                            }
                            result.success(isEnabled);
                            break;

                        // ==================== Preamp ====================
                        case "setPreamp":
                            double preampGain = call.argument("gain");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                DSPEngine.setPreamp((float) preampGain);
                            }
                            result.success(null);
                            break;
                        case "getPreamp":
                            float curPreamp = 0f;
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                curPreamp = DSPEngine.getPreamp();
                            }
                            result.success((double) curPreamp);
                            break;

                        // ==================== MBC Toggle ====================
                        case "enableMbc":
                            boolean mbcEnable = call.argument("enable");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                DSPEngine.enableMbc(mbcEnable);
                            }
                            result.success(null);
                            break;
                        case "isMbcEnabled":
                            boolean mbcOn = false;
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                mbcOn = DSPEngine.isMbcEnabled();
                            }
                            result.success(mbcOn);
                            break;

                        // bassboost
                        case "initBassBoost":

                            BassEq.init(AudioManager.AUDIO_SESSION_ID_GENERATE);
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
                            int strengthB = ((int) BassEq.getStrength());
                            result.success(strengthB);
                            break;
                        case "setBassBoostStrength":
                            int strengthBB = call.argument("strength");
                            BassEq.setStrength(strengthBB);
                            break;
                        // loudnessEnhancer (legacy init — still needed for session binding)
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

                        // ==================== DVC (Direct Volume Control) ====================
                        case "enableDvc":
                            DvcController.enable(getApplicationContext());
                            result.success(null);
                            break;
                        case "disableDvc":
                            DvcController.disable(getApplicationContext());
                            result.success(null);
                            break;
                        case "setDvcGain":
                            double dvcGainDb = call.argument("gain");
                            DvcController.setGain((float) dvcGainDb);
                            result.success(null);
                            break;
                        case "getDvcGain":
                            double dvcGainVal = (double) LoudnessControl.getTargetGain();
                            result.success(dvcGainVal);
                            break;
                        case "isDvcActive":
                            result.success(DvcController.isActive());
                            break;
                        case "getSystemVolume":
                            result.success(DvcController.getCurrentSystemVolume());
                            break;
                        case "getSystemMaxVolume":
                            result.success(DvcController.getMaxVolume());
                            break;

                        // DSP configurations
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
                            // speakers
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

                        case "getVocalLevel":
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                float vocalLevel = DSPEngine.getVocalLevel();
                                result.success(vocalLevel);
                            }
                            break;

                        case "setDSPXBass":
                            double bassGain = call.argument("xBass");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                DSPEngine.setDSPXBass((float) bassGain);
                            }
                            break;
                        case "setExtraBass":
                            double xtraGain = call.argument("extraBass");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                DSPEngine.setDSPx((float) xtraGain);
                            }
                            break;
                        case "setDSPPowerBass":
                            double powerBass = call.argument("powerBass");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                DSPEngine.setDSPPowerBass(((float) powerBass));
                            }
                            break;

                        case "setDSPXTreble":
                            double trebleGain = call.argument("trebleGain");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                DSPEngine.setDSPTreble((float) trebleGain);
                            }
                            break;
                        case "setDSPVolume":
                            double dspVolume = call.argument("dspVolume");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                DSPEngine.setDSPVolume(((float) dspVolume));
                            }
                            break;
                        case "setDspNoiseThreshold":
                            double noiseThreshold = call.argument("noiseThreshold");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                DSPEngine.setNoiseThreshold((float) noiseThreshold);
                            }
                            break;
                        // settings for tuner
                        case "setTunerBass":
                            double tBass = call.argument("tunerBass");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                DSPEngine.setBassTone((float) tBass);
                            }
                            break;
                        case "setCutOffFreq":
                            int tBasFreq = call.argument("tunerBassFreq");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                DSPEngine.setCutOffFrequencyForTunerBass(tBasFreq);
                            }
                            break;
                        case "setTrebleFreq":
                            double tTrebleFreq = call.argument("trebleFreq");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                DSPEngine.setFrequencyTrebleForTuner((float) tTrebleFreq);
                            }
                            break;
                        case "setTunerVocal":
                            double tVocal = call.argument("tunerVocal");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                DSPEngine.adjustTunerVocal((float) tVocal);
                            }
                            break;
                        // -------------------------- compressor settings
                        case "setPreGain":
                            double preGain = call.argument("preGain");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                DSPEngine.setPreGain((float) preGain);
                            }
                            break;
                        case "expandRatio":
                            double expandRatio = call.argument("expandRatio");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                DSPEngine.setExpanderRatio((float) expandRatio);
                            }
                            break;
                        case "kneeWidth":
                            double kneeWidth = call.argument("kneeWidth");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                DSPEngine.setKneeWidth((float) kneeWidth);
                            }
                            break;
                        // ------------------------end of compressor settings
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
                            int pPreset = (int) call.argument("preset");
                            ReverbEngine.setPreset(pPreset);
                            break;

                        case "getReverbPreset":
                            short g = ReverbEngine.getPreset();
                            result.success(((short) g));
                            break;
                        case "deleteManager":
                            String operation = call.argument("filePath");
                            assert operation != null;
                            File f = new File(operation);
                            if (f.exists() && f.isDirectory()) {
                                // Use a recursive method to delete the folder and its contents
                                if (DeleteManager.deleteFolder(f)) {
                                    showMessage(String.format("%s deleted successfully.",
                                            operation.split("/")[operation.split("/").length - 1]));
                                } else {
                                    showMessage("Failed to delete the folder.");
                                }
                            } else {
                                showMessage("Folder does not exist or is not a directory.");
                            }
                            break;
                        case "showNativeMessage":
                            String message = call.argument("message");
                            showMessage(message);
                            break;
                        // ==================== Custom DSP Room Effects ====================
                        case "dspSetReverbEnabled": {
                            boolean en = call.argument("enabled");
                            RoomEffectsProcessor.getInstance().setReverbEnabled(en);
                            result.success(null);
                            break;
                        }
                        case "dspSetRoomSize": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.getInstance().setRoomSize((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetDecay": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.getInstance().setDecay((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetDamping": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.getInstance().setDamping((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetPreDelay": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.getInstance().setPreDelay((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetDiffusion": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.getInstance().setDiffusion((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetReverbWetDry": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.getInstance().setReverbWetDry((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetStereoExpandEnabled": {
                            boolean en = call.argument("enabled");
                            RoomEffectsProcessor.getInstance().setStereoExpandEnabled(en);
                            result.success(null);
                            break;
                        }
                        case "dspSetStereoWidth": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.getInstance().setStereoWidth((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetCrossfeedEnabled": {
                            boolean en = call.argument("enabled");
                            RoomEffectsProcessor.getInstance().setCrossfeedEnabled(en);
                            result.success(null);
                            break;
                        }
                        case "dspSetCrossfeedParams": {
                            double cutoff = call.argument("cutoff");
                            double feed = call.argument("feed");
                            RoomEffectsProcessor.getInstance().setCrossfeedParams((float) cutoff, (float) feed);
                            result.success(null);
                            break;
                        }
                        case "dspSetCrossfadeBypass": {
                            boolean bypass = call.argument("enabled");
                            RoomEffectsProcessor.getInstance().setCrossfadeBypass(bypass);
                            result.success(null);
                            break;
                        }

                        // ==================== 32-Band Graphic EQ ====================
                        case "setGraphicBandGain":
                            int gBand = call.argument("band");
                            double gGain = call.argument("gain");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                DSPEngine.setGraphicBandGain(gBand, (float) gGain);
                            }
                            result.success(null);
                            break;
                        case "getGraphicBandGain":
                            int gBandGet = call.argument("band");
                            float gBandGain = 0f;
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                gBandGain = DSPEngine.getGraphicBandGain(gBandGet);
                            }
                            result.success(gBandGain);
                            break;
                        case "setGraphicAllBands":
                            ArrayList<Double> gGains = call.argument("gains");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && gGains != null) {
                                float[] gainArr = new float[gGains.size()];
                                for (int gi = 0; gi < gGains.size(); gi++) {
                                    gainArr[gi] = gGains.get(gi).floatValue();
                                }
                                DSPEngine.setGraphicAllBands(gainArr);
                            }
                            result.success(null);
                            break;
                        case "getGraphicAllBands":
                            ArrayList<Double> allGains = new ArrayList<>();
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                float[] raw = DSPEngine.getGraphicAllBands();
                                for (float v : raw) allGains.add((double) v);
                            }
                            result.success(allGains);
                            break;

                        // ==================== 32-Band Parametric EQ ====================
                        case "setParametricBand":
                            int pBand = call.argument("band");
                            double pFreq = call.argument("freq");
                            double pGainV = call.argument("gain");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                DSPEngine.setParametricBand(pBand, (float) pFreq, (float) pGainV);
                            }
                            result.success(null);
                            break;
                        case "setParametricAllBands":
                            ArrayList<Double> pFreqs = call.argument("freqs");
                            ArrayList<Double> pGains = call.argument("gains");
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && pFreqs != null && pGains != null) {
                                float[] freqArr = new float[pFreqs.size()];
                                float[] pGainArr = new float[pGains.size()];
                                for (int pi = 0; pi < pFreqs.size(); pi++) {
                                    freqArr[pi] = pFreqs.get(pi).floatValue();
                                    pGainArr[pi] = pGains.get(pi).floatValue();
                                }
                                DSPEngine.setParametricAllBands(freqArr, pGainArr);
                            }
                            result.success(null);
                            break;

                        // ==================== Device Detection ====================
                        case "isDynamicsProcessingAvailable":
                            result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.P);
                            break;
                        case "getAudioOutputType":
                            String outputType = AudioOutputDetector.getAudioOutputType(getApplicationContext());
                            result.success(outputType);
                            break;

                        // ==================== Lyrics ====================
                        case "readLyrics": {
                            String lyrFilePath = call.argument("filePath");
                            String lyrText = LyricsManager.readLyrics(lyrFilePath);
                            result.success(lyrText);
                            break;
                        }
                        case "writeLyrics": {
                            String lyrFilePath = call.argument("filePath");
                            String lyrContent = call.argument("lyrics");

                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                                // Android 9 and below: direct file access
                                result.success(LyricsManager.writeLyricsDirect(lyrFilePath, lyrContent));
                            } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                                // Android 10: requestLegacyExternalStorage=true allows direct access
                                result.success(LyricsManager.writeLyricsDirect(lyrFilePath, lyrContent));
                            } else {
                                // Android 11+: MediaStore + createWriteRequest
                                File modified = LyricsManager.prepareModifiedFile(
                                        getCacheDir(), lyrFilePath, lyrContent);
                                if (modified == null) {
                                    result.success(false);
                                    break;
                                }
                                Uri uri = LyricsManager.getMediaUri(getContentResolver(), lyrFilePath);
                                if (uri == null) {
                                    modified.delete();
                                    result.success(false);
                                    break;
                                }
                                // Store pending state and request write permission
                                pendingWriteResult = result;
                                pendingWriteUri = uri;
                                pendingModifiedFile = modified;
                                try {
                                    PendingIntent pi = MediaStore.createWriteRequest(
                                            getContentResolver(), Collections.singletonList(uri));
                                    IntentSenderRequest req = new IntentSenderRequest.Builder(
                                            pi.getIntentSender()).build();
                                    writeRequestLauncher.launch(req);
                                } catch (Exception e) {
                                    e.printStackTrace();
                                    modified.delete();
                                    pendingWriteResult = null;
                                    pendingWriteUri = null;
                                    pendingModifiedFile = null;
                                    result.success(false);
                                }
                            }
                            break;
                        }

                        // ==================== projectM Visualizer ====================
                        case "projectm_init": {
                            int pmWidth = call.argument("width");
                            int pmHeight = call.argument("height");
                            long textureId = projectMRenderer.init(pmWidth, pmHeight);
                            result.success(textureId);
                            break;
                        }
                        case "projectm_start": {
                            projectMRenderer.start();
                            result.success(null);
                            break;
                        }
                        case "projectm_stop": {
                            projectMRenderer.stop();
                            result.success(null);
                            break;
                        }
                        case "projectm_release": {
                            projectMRenderer.release();
                            result.success(null);
                            break;
                        }
                        case "projectm_set_preset": {
                            String presetPath = call.argument("path");
                            projectMRenderer.loadPreset(presetPath);
                            result.success(null);
                            break;
                        }
                        case "projectm_next_preset": {
                            projectMRenderer.nextPreset();
                            result.success(projectMRenderer.getCurrentPresetName());
                            break;
                        }
                        case "projectm_prev_preset": {
                            projectMRenderer.previousPreset();
                            result.success(projectMRenderer.getCurrentPresetName());
                            break;
                        }
                        case "projectm_load_preset_index": {
                            int pmIndex = call.argument("index");
                            projectMRenderer.loadPresetByIndex(pmIndex);
                            result.success(projectMRenderer.getCurrentPresetName());
                            break;
                        }
                        case "projectm_list_presets": {
                            result.success(new ArrayList<>(projectMRenderer.getPresetNames()));
                            break;
                        }
                        case "projectm_current_preset": {
                            result.success(projectMRenderer.getCurrentPresetName());
                            break;
                        }
                        case "projectm_set_fps": {
                            int pmFps = call.argument("fps");
                            projectMRenderer.setFps(pmFps);
                            result.success(null);
                            break;
                        }
                        case "projectm_set_beat_sensitivity": {
                            double pmSens = call.argument("sensitivity");
                            projectMRenderer.setBeatSensitivity((float) pmSens);
                            result.success(null);
                            break;
                        }
                        case "projectm_set_preset_duration": {
                            double pmDur = call.argument("duration");
                            projectMRenderer.setPresetDuration(pmDur);
                            result.success(null);
                            break;
                        }
                        case "projectm_set_preset_locked": {
                            boolean pmLocked = call.argument("locked");
                            projectMRenderer.setPresetLocked(pmLocked);
                            result.success(null);
                            break;
                        }
                        case "projectm_set_size": {
                            int pmW = call.argument("width");
                            int pmH = call.argument("height");
                            projectMRenderer.setSize(pmW, pmH);
                            result.success(null);
                            break;
                        }

                        default:
                            result.notImplemented();
                            break;
                    }
                });
    }

    protected void showMessage(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }

    private class HeadphoneService extends BroadcastReceiver {
        private static final long DOUBLE_CLICK_TIME_THRESHOLD = 500; // Time threshold for a double click in
                                                                     // milliseconds
        private long lastClickTime = 0;

        @Override
        public void onReceive(Context context, Intent intent) {
            if (intent.getAction() != null && intent.getAction().equals(AudioManager.ACTION_HEADSET_PLUG)) {
                long currentTime = System.currentTimeMillis();

                // Check for a double click by comparing the time between two clicks
                if (currentTime - lastClickTime < DOUBLE_CLICK_TIME_THRESHOLD) {
                    // Double click detected, perform your action here (e.g., play the next track)
                    playNextTrack();
                }

                lastClickTime = currentTime;
            }
        }

        private void playNextTrack() {
            // Add your logic to play the next track here
            Toast.makeText(getApplicationContext(), "Playing next track", Toast.LENGTH_SHORT).show();
            // Implement the code to start playing the next track, e.g., with a media player
            // or your audio playback logic.
        }
    }

}