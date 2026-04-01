package x.a.zix;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.media.AudioManager;
import android.media.MediaMetadataRetriever;
import android.media.audiofx.Visualizer;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.view.KeyEvent;
import android.widget.Toast;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.IntentSenderRequest;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.NonNull;
import androidx.activity.EdgeToEdge;

import com.ryanheise.audioservice.AudioServiceFragmentActivity;

import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

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

    // Scoped-storage write state
    private ActivityResultLauncher<IntentSenderRequest> writeRequestLauncher;
    private MethodChannel.Result pendingWriteResult;
    private Uri pendingWriteUri;
    private File pendingModifiedFile;
    private String pendingWriteFilePath;

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
                    if (ok && pendingWriteFilePath != null) {
                        TagWriter.scanFile(getApplicationContext(), pendingWriteFilePath);
                    }
                    pendingWriteResult.success(ok);
                    pendingWriteResult = null;
                    pendingWriteUri = null;
                    pendingModifiedFile = null;
                    pendingWriteFilePath = null;
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

        // Stem separation EventChannel
        EventChannel stemEventChannel = new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(), "eq_app/stem_progress");
        StemSeparationService.setupEventChannel(stemEventChannel);

        // FFT Visualizer EventChannels (replaces android.media.audiofx.Visualizer)
        EventChannel fftChannel = new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(), "eq_app/fft_bands");
        fftChannel.setStreamHandler(new EventChannel.StreamHandler() {
            @Override public void onListen(Object arguments, EventChannel.EventSink events) {
                VisualizerTapProcessor.setFftSink(events);
            }
            @Override public void onCancel(Object arguments) {
                VisualizerTapProcessor.setFftSink(null);
            }
        });
        EventChannel waveformChannel = new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(), "eq_app/waveform");
        waveformChannel.setStreamHandler(new EventChannel.StreamHandler() {
            @Override public void onListen(Object arguments, EventChannel.EventSink events) {
                VisualizerTapProcessor.setWaveformSink(events);
            }
            @Override public void onCancel(Object arguments) {
                VisualizerTapProcessor.setWaveformSink(null);
            }
        });

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
                            VisualizerTapProcessor.setFrameRate(frameRate);
                            break;

                        case "setVizSmoothing": {
                            double attack = call.argument("attack");
                            double decay = call.argument("decay");
                            VisualizerTapProcessor.setSmoothing((float) attack, (float) decay);
                            break;
                        }

                        case "setVizGain": {
                            double gain = call.argument("gain");
                            VisualizerTapProcessor.setGain((float) gain);
                            break;
                        }

                        case "init":
                            // Legacy — EQ + MBC now handled by C++ DSP pipeline
                            break;

                        case "enableEq":
                            boolean enableEq = call.argument("enable");
                            RoomEffectsProcessor.broadcastEqEnabled(enableEq);
                            break;
                        case "isEnabled":
                            // EQ is now always available (C++ pipeline, no API level requirement)
                            result.success(true);
                            break;

                        // ==================== Preamp ====================
                        case "setPreamp":
                            double preampGain = call.argument("gain");
                            RoomEffectsProcessor.broadcastPreampGain((float) preampGain);
                            result.success(null);
                            break;
                        case "getPreamp":
                            result.success((double) RoomEffectsProcessor.getCachedPreampGain());
                            break;

                        // ==================== MBC Toggle ====================
                        case "enableMbc":
                            boolean mbcEnable = call.argument("enable");
                            RoomEffectsProcessor.broadcastMbcEnabled(mbcEnable);
                            result.success(null);
                            break;
                        case "isMbcEnabled":
                            result.success(RoomEffectsProcessor.isCachedMbcEnabled());
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

                        // ==================== MBC Compressor Settings ====================
                        case "setDspNoiseThreshold": {
                            double noiseThreshold = call.argument("noiseThreshold");
                            RoomEffectsProcessor.broadcastMbcNoiseGate((float) noiseThreshold);
                            result.success(null);
                            break;
                        }
                        case "setPreGain": {
                            double preGain = call.argument("preGain");
                            RoomEffectsProcessor.broadcastMbcPreGain((float) preGain);
                            result.success(null);
                            break;
                        }
                        case "expandRatio": {
                            double expandRatio = call.argument("expandRatio");
                            RoomEffectsProcessor.broadcastMbcExpanderRatio((float) expandRatio);
                            result.success(null);
                            break;
                        }
                        case "kneeWidth": {
                            double kneeWidth = call.argument("kneeWidth");
                            RoomEffectsProcessor.broadcastMbcKneeWidth((float) kneeWidth);
                            result.success(null);
                            break;
                        }

                        // ==================== Tone Controls (Bass/Treble) ====================
                        case "dspSetToneEnabled": {
                            boolean en = call.argument("enabled");
                            RoomEffectsProcessor.broadcastToneEnabled(en);
                            result.success(null);
                            break;
                        }
                        case "dspSetBassGain": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.broadcastBassGain((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetBassFreq": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.broadcastBassFreq((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetBassQ": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.broadcastBassQ((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetTrebleGain": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.broadcastTrebleGain((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetTrebleFreq": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.broadcastTrebleFreq((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetTrebleQ": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.broadcastTrebleQ((float) v);
                            result.success(null);
                            break;
                        }

                        // ==================== Output Limiter ====================
                        case "dspSetLimiterEnabled": {
                            boolean en = call.argument("enabled");
                            RoomEffectsProcessor.broadcastLimiterEnabled(en);
                            result.success(null);
                            break;
                        }
                        case "dspSetLimiterCeiling": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.broadcastLimiterCeiling((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetLimiterRelease": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.broadcastLimiterRelease((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetLimiterKnee": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.broadcastLimiterKnee((float) v);
                            result.success(null);
                            break;
                        }

                        // Legacy DSP stubs — no-ops for backward compatibility
                        case "initDSPEngine":
                        case "enableDSP":
                        case "disposeDSP":
                        case "setDSPSpeakers":
                        case "setDSPXBass":
                        case "setExtraBass":
                        case "setDSPPowerBass":
                        case "setDSPXTreble":
                        case "setDSPVolume":
                        case "setTunerBass":
                        case "setCutOffFreq":
                        case "setTrebleFreq":
                        case "setTunerVocal":
                            // Removed — all DSP processing handled by C++ pipeline
                            break;
                        case "getVocalLevel":
                            result.success(0.0f);
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
                            RoomEffectsProcessor.broadcastReverbEnabled(en);
                            result.success(null);
                            break;
                        }
                        case "dspSetRoomSize": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.broadcastRoomSize((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetDecay": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.broadcastDecay((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetDamping": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.broadcastDamping((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetPreDelay": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.broadcastPreDelay((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetDiffusion": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.broadcastDiffusion((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetReverbWetDry": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.broadcastReverbWetDry((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetStereoExpandEnabled": {
                            boolean en = call.argument("enabled");
                            RoomEffectsProcessor.broadcastStereoExpandEnabled(en);
                            result.success(null);
                            break;
                        }
                        case "dspSetStereoWidth": {
                            double v = call.argument("value");
                            RoomEffectsProcessor.broadcastStereoWidth((float) v);
                            result.success(null);
                            break;
                        }
                        case "dspSetCrossfeedEnabled": {
                            boolean en = call.argument("enabled");
                            RoomEffectsProcessor.broadcastCrossfeedEnabled(en);
                            result.success(null);
                            break;
                        }
                        case "dspSetCrossfeedParams": {
                            double cutoff = call.argument("cutoff");
                            double feed = call.argument("feed");
                            RoomEffectsProcessor.broadcastCrossfeedParams((float) cutoff, (float) feed);
                            result.success(null);
                            break;
                        }

                        // ==================== 32-Band Graphic EQ ====================
                        case "setGraphicBandGain":
                            int gBand = call.argument("band");
                            double gGain = call.argument("gain");
                            RoomEffectsProcessor.broadcastGraphicBandGain(gBand, (float) gGain);
                            result.success(null);
                            break;
                        case "getGraphicBandGain":
                            // No longer queried from DynamicsProcessing — Dart holds the state
                            result.success(0.0f);
                            break;
                        case "setGraphicAllBands":
                            ArrayList<Double> gGains = call.argument("gains");
                            if (gGains != null) {
                                float[] gainArr = new float[gGains.size()];
                                for (int gi = 0; gi < gGains.size(); gi++) {
                                    gainArr[gi] = gGains.get(gi).floatValue();
                                }
                                RoomEffectsProcessor.broadcastGraphicAllBands(gainArr);
                            }
                            result.success(null);
                            break;
                        case "getGraphicAllBands":
                            // No longer queried from DynamicsProcessing — Dart holds the state
                            result.success(new ArrayList<Double>());
                            break;

                        // ==================== 32-Band Parametric EQ ====================
                        case "setParametricBand": {
                            int pBand = call.argument("band");
                            double pFreq = call.argument("freq");
                            double pGainV = call.argument("gain");
                            double pQ = call.argument("q") != null ? (double) call.argument("q") : 1.4;
                            int pFilterType = call.argument("filterType") != null ? (int) call.argument("filterType") : 0;
                            boolean pEnabled = call.argument("enabled") != null ? (boolean) call.argument("enabled") : true;
                            RoomEffectsProcessor.broadcastParametricBand(pBand, (float) pFreq,
                                    (float) pGainV, (float) pQ, pFilterType, pEnabled);
                            result.success(null);
                            break;
                        }
                        case "setParametricAllBands": {
                            ArrayList<Double> pFreqs = call.argument("freqs");
                            ArrayList<Double> pGains = call.argument("gains");
                            ArrayList<Double> pQs = call.argument("qs");
                            if (pFreqs != null && pGains != null) {
                                int pCount = pFreqs.size();
                                float[] freqArr = new float[pCount];
                                float[] pGainArr = new float[pCount];
                                float[] qArr = new float[pCount];
                                for (int pi = 0; pi < pCount; pi++) {
                                    freqArr[pi] = pFreqs.get(pi).floatValue();
                                    pGainArr[pi] = pGains.get(pi).floatValue();
                                    qArr[pi] = (pQs != null && pi < pQs.size()) ? pQs.get(pi).floatValue() : 1.4f;
                                }
                                RoomEffectsProcessor.broadcastParametricAllBands(freqArr, pGainArr, qArr, pCount);
                            }
                            result.success(null);
                            break;
                        }

                        // ==================== Speaker Correction EQ (AutoEq) ====================
                        case "setSpeakerEqEnabled": {
                            boolean spkEn = call.argument("enabled");
                            RoomEffectsProcessor.broadcastSpeakerEqEnabled(spkEn);
                            result.success(null);
                            break;
                        }
                        case "setSpeakerEqBands": {
                            ArrayList<Double> spkFreqs = call.argument("freqs");
                            ArrayList<Double> spkGains = call.argument("gains");
                            ArrayList<Double> spkQs = call.argument("qs");
                            ArrayList<Integer> spkTypes = call.argument("types");
                            if (spkFreqs != null && spkGains != null && spkQs != null && spkTypes != null) {
                                int spkCount = spkFreqs.size();
                                float[] sf = new float[spkCount];
                                float[] sg = new float[spkCount];
                                float[] sq = new float[spkCount];
                                int[] st = new int[spkCount];
                                for (int si = 0; si < spkCount; si++) {
                                    sf[si] = spkFreqs.get(si).floatValue();
                                    sg[si] = spkGains.get(si).floatValue();
                                    sq[si] = spkQs.get(si).floatValue();
                                    st[si] = spkTypes.get(si);
                                }
                                RoomEffectsProcessor.broadcastSpeakerEqBands(sf, sg, sq, st, spkCount);
                            }
                            result.success(null);
                            break;
                        }
                        case "clearSpeakerEq": {
                            RoomEffectsProcessor.broadcastClearSpeakerEq();
                            result.success(null);
                            break;
                        }

                        // ==================== Stem Separation ====================
                        case "separateStems": {
                            String sepFilePath = call.argument("filePath");
                            String sepOutputDir = call.argument("outputDir");
                            Intent sepIntent = new Intent(MainActivity.this, StemSeparationService.class);
                            sepIntent.putExtra("filePath", sepFilePath);
                            sepIntent.putExtra("outputDir", sepOutputDir);
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(sepIntent);
                            } else {
                                startService(sepIntent);
                            }
                            result.success(true);
                            break;
                        }
                        case "cancelStemSeparation": {
                            Intent cancelIntent = new Intent(MainActivity.this, StemSeparationService.class);
                            cancelIntent.setAction("CANCEL");
                            startService(cancelIntent);
                            result.success(null);
                            break;
                        }

                        // ==================== Stem Mixer ====================
                        case "loadStems": {
                            String vocalsPath = call.argument("vocals");
                            String drumsPath = call.argument("drums");
                            String bassPath = call.argument("bass");
                            String otherPath = call.argument("other");
                            String[] stemPaths = {vocalsPath, drumsPath, bassPath, otherPath};
                            RoomEffectsProcessor.broadcastLoadStems(stemPaths);
                            result.success(true);
                            break;
                        }
                        case "unloadStems": {
                            RoomEffectsProcessor.broadcastUnloadStems();
                            result.success(null);
                            break;
                        }
                        case "activateStemMode": {
                            RoomEffectsProcessor.broadcastStemModeActive(true);
                            result.success(null);
                            break;
                        }
                        case "deactivateStemMode": {
                            RoomEffectsProcessor.broadcastStemModeActive(false);
                            result.success(null);
                            break;
                        }
                        case "setStemVolume": {
                            int stemIdx = call.argument("stem");
                            double stemVol = call.argument("volume");
                            RoomEffectsProcessor.broadcastStemVolume(stemIdx, (float) stemVol);
                            result.success(null);
                            break;
                        }
                        case "setStemMute": {
                            int stemMuteIdx = call.argument("stem");
                            boolean stemMuted = call.argument("muted");
                            RoomEffectsProcessor.broadcastStemMute(stemMuteIdx, stemMuted);
                            result.success(null);
                            break;
                        }
                        case "setStemSolo": {
                            int stemSoloIdx = call.argument("stem");
                            boolean stemSoloed = call.argument("soloed");
                            RoomEffectsProcessor.broadcastStemSolo(stemSoloIdx, stemSoloed);
                            result.success(null);
                            break;
                        }
                        case "stemSeek": {
                            long stemSeekPos = ((Number) call.argument("samplePosition")).longValue();
                            RoomEffectsProcessor.broadcastStemSeek(stemSeekPos);
                            result.success(null);
                            break;
                        }
                        case "checkStemsExist": {
                            String checkPath = call.argument("dirPath");
                            if (checkPath != null) {
                                File dir = new File(checkPath);
                                boolean exists = dir.exists()
                                    && new File(dir, "vocals.wav").exists()
                                    && new File(dir, "drums.wav").exists()
                                    && new File(dir, "bass.wav").exists()
                                    && new File(dir, "other.wav").exists();
                                result.success(exists);
                            } else {
                                result.success(false);
                            }
                            break;
                        }

                        // ==================== Global EQ (System-Wide) ====================
                        case "enableGlobalEq": {
                            boolean globalOn = call.argument("enable");
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
                                result.success(false);
                                break;
                            }
                            if (globalOn) {
                                Intent svc = new Intent(getApplicationContext(), GlobalEqService.class);
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                    startForegroundService(svc);
                                } else {
                                    startService(svc);
                                }
                            } else {
                                stopService(new Intent(getApplicationContext(), GlobalEqService.class));
                            }
                            result.success(true);
                            break;
                        }
                        case "isGlobalEqEnabled":
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                result.success(GlobalEqSessionManager.isEnabled());
                            } else {
                                result.success(false);
                            }
                            break;
                        case "isGlobalEqAvailable":
                            result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.P);
                            break;

                        // ==================== EQ Mode Notification ====================
                        case "startEqModeService": {
                            String preset = call.argument("preset");
                            Intent svc = new Intent(getApplicationContext(), EqModeService.class);
                            if (preset != null) svc.putExtra(EqModeService.EXTRA_PRESET, preset);
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(svc);
                            } else {
                                startService(svc);
                            }
                            result.success(true);
                            break;
                        }
                        case "stopEqModeService":
                            stopService(new Intent(getApplicationContext(), EqModeService.class));
                            result.success(true);
                            break;
                        case "updateEqModePreset": {
                            String preset = call.argument("preset");
                            Intent svc = new Intent(getApplicationContext(), EqModeService.class);
                            if (preset != null) svc.putExtra(EqModeService.EXTRA_PRESET, preset);
                            startService(svc);
                            result.success(true);
                            break;
                        }

                        case "getPlayingApps": {
                            PackageManager pm = getPackageManager();
                            List<String> pkgList = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                                    ? GlobalEqService.getPlayingApps()
                                    : new ArrayList<>();
                            List<Map<String, String>> appInfoList = new ArrayList<>();
                            for (String pkg : pkgList) {
                                Map<String, String> info = new HashMap<>();
                                info.put("package", pkg);
                                try {
                                    ApplicationInfo ai = pm.getApplicationInfo(pkg, 0);
                                    info.put("name", pm.getApplicationLabel(ai).toString());
                                } catch (PackageManager.NameNotFoundException e) {
                                    info.put("name", pkg.contains(".")
                                            ? pkg.substring(pkg.lastIndexOf('.') + 1)
                                            : pkg);
                                }
                                appInfoList.add(info);
                            }
                            result.success(appInfoList);
                            break;
                        }
                        case "getAppIcon": {
                            String iconPkg = call.argument("package");
                            if (iconPkg == null) { result.success(null); break; }
                            final String finalPkg = iconPkg;
                            new Thread(() -> {
                                try {
                                    PackageManager ipm = getPackageManager();
                                    Drawable drawable = ipm.getApplicationIcon(finalPkg);
                                    Bitmap bitmap = drawableToBitmap(drawable);
                                    ByteArrayOutputStream baos = new ByteArrayOutputStream();
                                    bitmap.compress(Bitmap.CompressFormat.PNG, 90, baos);
                                    byte[] bytes = baos.toByteArray();
                                    new Handler(Looper.getMainLooper()).post(() -> result.success(bytes));
                                } catch (Exception e) {
                                    new Handler(Looper.getMainLooper()).post(() -> result.success(null));
                                }
                            }).start();
                            break;
                        }

                        // ==================== Battery Optimization ====================
                        case "isBatteryOptimizationDisabled": {
                            android.os.PowerManager pm =
                                    (android.os.PowerManager) getSystemService(POWER_SERVICE);
                            result.success(pm != null &&
                                    pm.isIgnoringBatteryOptimizations(getPackageName()));
                            break;
                        }
                        case "requestDisableBatteryOptimization": {
                            try {
                                Intent batteryIntent = new Intent(
                                        android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
                                batteryIntent.setData(android.net.Uri.parse("package:" + getPackageName()));
                                startActivity(batteryIntent);
                                result.success(true);
                            } catch (Exception e) {
                                result.success(false);
                            }
                            break;
                        }

                        // ==================== Device Detection ====================
                        case "isDynamicsProcessingAvailable":
                            // Always true — C++ DSP pipeline has no API level requirement
                            result.success(true);
                            break;
                        case "getAudioOutputType":
                            String outputType = AudioOutputDetector.getAudioOutputType(getApplicationContext());
                            result.success(outputType);
                            break;

                        // ==================== Audio Metadata Extraction ====================
                        case "extractAudioMetadata": {
                            String metaUrl = call.argument("url");
                            Map<String, String> metaHeaders = call.argument("headers");
                            String artPath = call.argument("artworkPath");
                            if (metaHeaders == null) metaHeaders = new HashMap<>();
                            final Map<String, String> finalHeaders = metaHeaders;

                            // AtomicBoolean prevents double result.success() from
                            // both the worker thread and the timeout handler.
                            final AtomicBoolean completed = new AtomicBoolean(false);
                            final Handler mainHandler = new Handler(Looper.getMainLooper());

                            // Run on background thread — MMR does network I/O
                            Thread worker = new Thread(() -> {
                                Map<String, Object> metadata = new HashMap<>();
                                MediaMetadataRetriever mmr = new MediaMetadataRetriever();
                                boolean success = false;
                                try {
                                    mmr.setDataSource(metaUrl, finalHeaders);
                                    success = true; // setDataSource didn't throw

                                    String title = mmr.extractMetadata(
                                            MediaMetadataRetriever.METADATA_KEY_TITLE);
                                    String artist = mmr.extractMetadata(
                                            MediaMetadataRetriever.METADATA_KEY_ARTIST);
                                    String album = mmr.extractMetadata(
                                            MediaMetadataRetriever.METADATA_KEY_ALBUM);
                                    String durationStr = mmr.extractMetadata(
                                            MediaMetadataRetriever.METADATA_KEY_DURATION);

                                    if (title != null) metadata.put("title", title);
                                    if (artist != null) metadata.put("artist", artist);
                                    if (album != null) metadata.put("album", album);
                                    if (durationStr != null) {
                                        try {
                                            metadata.put("durationMs",
                                                    Integer.parseInt(durationStr));
                                        } catch (NumberFormatException ignored) {}
                                    }

                                    // Extract embedded artwork
                                    byte[] art = mmr.getEmbeddedPicture();
                                    if (art != null && artPath != null) {
                                        try (FileOutputStream fos =
                                                     new FileOutputStream(artPath)) {
                                            fos.write(art);
                                            metadata.put("hasArtwork", true);
                                        } catch (Exception ignored) {}
                                    }
                                } catch (Exception e) {
                                    e.printStackTrace();
                                } finally {
                                    try { mmr.release(); } catch (Exception ignored) {}
                                }

                                // Return result on main thread (required by Flutter).
                                // success=true → return metadata map (even if empty — file
                                // has no tags). success=false → return null (extraction
                                // failed, should retry later).
                                final boolean ok = success;
                                final Map<String, Object> md = metadata;
                                if (completed.compareAndSet(false, true)) {
                                    mainHandler.post(() -> result.success(ok ? md : null));
                                }
                            });
                            worker.start();

                            // 15-second timeout — MMR has no internal read timeout
                            // and can hang indefinitely on slow/stalled connections.
                            mainHandler.postDelayed(() -> {
                                if (completed.compareAndSet(false, true)) {
                                    worker.interrupt();
                                    result.success(null); // null = failed, retry later
                                }
                            }, 15000);
                            break;
                        }

                        // ==================== Audio Fingerprinting ====================
                        case "generateFingerprint": {
                            String fpPath = call.argument("filePath");
                            final AtomicBoolean fpDone = new AtomicBoolean(false);
                            final Handler fpHandler = new Handler(Looper.getMainLooper());

                            Thread fpWorker = new Thread(() -> {
                                Map<String, Object> fpResult = FingerprintEngine.generateFingerprint(fpPath);
                                if (fpDone.compareAndSet(false, true)) {
                                    fpHandler.post(() -> result.success(fpResult));
                                }
                            });
                            fpWorker.start();

                            // 30-second timeout for decoding + fingerprinting
                            fpHandler.postDelayed(() -> {
                                if (fpDone.compareAndSet(false, true)) {
                                    fpWorker.interrupt();
                                    result.success(null);
                                }
                            }, 30000);
                            break;
                        }

                        // ==================== Tag Writing ====================
                        case "writeTags": {
                            String wtPath = call.argument("filePath");
                            Map<String, String> wtTags = call.argument("tags");
                            String wtArtwork = call.argument("artworkPath");

                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                                // Android 10 and below: direct file write
                                boolean ok = TagWriter.writeTagsDirect(wtPath, wtTags, wtArtwork);
                                if (ok) TagWriter.scanFile(getApplicationContext(), wtPath);
                                result.success(ok);
                            } else {
                                // Android 11+: scoped storage via MediaStore
                                File modified = TagWriter.prepareModifiedFile(
                                        getCacheDir(), wtPath, wtTags, wtArtwork);
                                if (modified == null) {
                                    result.success(false);
                                    break;
                                }
                                Uri uri = LyricsManager.getMediaUri(getContentResolver(), wtPath);
                                if (uri == null) {
                                    modified.delete();
                                    result.success(false);
                                    break;
                                }
                                pendingWriteResult = result;
                                pendingWriteUri = uri;
                                pendingModifiedFile = modified;
                                pendingWriteFilePath = wtPath;
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
                                    pendingWriteFilePath = null;
                                    result.success(false);
                                }
                            }
                            break;
                        }
                        case "scanMediaFile": {
                            String scanPath = call.argument("filePath");
                            TagWriter.scanFile(getApplicationContext(), scanPath);
                            result.success(null);
                            break;
                        }

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
                        case "projectm_set_mesh_size": {
                            int meshW = call.argument("width");
                            int meshH = call.argument("height");
                            projectMRenderer.setMeshSize(meshW, meshH);
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

    private static Bitmap drawableToBitmap(Drawable drawable) {
        if (drawable instanceof BitmapDrawable) {
            Bitmap bmp = ((BitmapDrawable) drawable).getBitmap();
            if (bmp != null) return bmp;
        }
        int w = Math.max(drawable.getIntrinsicWidth(), 1);
        int h = Math.max(drawable.getIntrinsicHeight(), 1);
        Bitmap bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        drawable.setBounds(0, 0, canvas.getWidth(), canvas.getHeight());
        drawable.draw(canvas);
        return bitmap;
    }

}