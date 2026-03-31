package x.a.zix;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.audio.BaseAudioProcessor;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import io.flutter.plugin.common.EventChannel;

/**
 * Media3 AudioProcessor that taps PCM audio for visualization.
 *
 * Two visualization paths:
 *   1. ProjectM: raw PCM via AtomicReference (existing)
 *   2. Flutter visualizers: PCM → C++ FFT → 64 log-frequency bands via EventChannel
 *
 * The C++ FFT replaces Android's Visualizer API, eliminating the need for
 * an audio session ID. PCM is tapped directly from ExoPlayer's pipeline.
 */
public class VisualizerTapProcessor extends BaseAudioProcessor {
    private static final String TAG = "VisualizerTap";

    // All player-attached instances
    private static final CopyOnWriteArrayList<VisualizerTapProcessor> playerInstances =
            new CopyOnWriteArrayList<>();

    // Shared PCM buffer across all instances — projectM render thread reads from here
    private static final AtomicReference<float[]> latestPcm = new AtomicReference<>(null);

    // Shared tap state — broadcast to all instances
    private static volatile boolean tapEnabledGlobal = false;

    // FFT visualization via EventChannel
    private static volatile EventChannel.EventSink fftSink;
    private static volatile EventChannel.EventSink waveformSink;
    private static ScheduledExecutorService vizThread;
    private static final Handler mainHandler = new Handler(Looper.getMainLooper());
    private static volatile boolean fftEnabled = false;

    // Singleton kept for ProjectMRenderer to call getLatestPcm() / setTapEnabled()
    private static VisualizerTapProcessor singleton;

    // Native FFT methods (implemented in jni_bridge.cpp)
    private static native void nativeInitFFT();
    private static native void nativeDestroyFFT();
    private static native void nativePushSamples(float[] samples, int numFrames);
    private static native float[] nativeComputeBands();
    private static native byte[] nativeGetWaveform();
    private static native void nativeSetSmoothing(float attack, float decay);
    private static native void nativeSetGain(float gain);

    static {
        System.loadLibrary("eq_app");
    }

    public static VisualizerTapProcessor getInstance() {
        if (singleton == null) {
            singleton = new VisualizerTapProcessor();
        }
        return singleton;
    }

    public static boolean hasInstance() {
        return !playerInstances.isEmpty();
    }

    /**
     * Called by just_audio's AudioPlayer.java via reflection.
     * Each ExoPlayer gets its own instance with independent buffer state.
     */
    public static VisualizerTapProcessor createPlayerInstance() {
        VisualizerTapProcessor p = new VisualizerTapProcessor();
        playerInstances.add(p);
        Log.i(TAG, "Player instance created, total: " + playerInstances.size());
        return p;
    }

    private int sampleRate = 44100;

    private VisualizerTapProcessor() {}

    // ---- BaseAudioProcessor overrides ----

    @Override
    protected AudioFormat onConfigure(AudioFormat inputAudioFormat)
            throws UnhandledAudioFormatException {
        int encoding = inputAudioFormat.encoding;
        if (encoding != C.ENCODING_PCM_16BIT && encoding != C.ENCODING_PCM_FLOAT) {
            throw new UnhandledAudioFormatException(inputAudioFormat);
        }
        if (inputAudioFormat.channelCount != 2) {
            Log.w(TAG, "Non-stereo audio (" + inputAudioFormat.channelCount + "ch), passing through");
            return AudioFormat.NOT_SET;
        }

        sampleRate = inputAudioFormat.sampleRate;
        Log.i(TAG, "Configured: " + sampleRate + "Hz, encoding=" + encoding);
        return inputAudioFormat;
    }

    @Override
    public void queueInput(ByteBuffer inputBuffer) {
        if (!inputBuffer.hasRemaining()) return;

        int remaining = inputBuffer.remaining();
        int encoding = inputAudioFormat.encoding;
        int bytesPerSample = (encoding == C.ENCODING_PCM_FLOAT) ? 4 : 2;
        int numFrames = remaining / (bytesPerSample * 2); // stereo

        if (numFrames <= 0) {
            inputBuffer.position(inputBuffer.limit());
            return;
        }

        // Pass audio through unchanged via BaseAudioProcessor buffer management
        ByteBuffer outputBuffer = replaceOutputBuffer(remaining);
        outputBuffer.put(inputBuffer);
        outputBuffer.flip();

        // If either tap (projectM) or FFT (Flutter visualizer) is enabled, extract PCM
        if (tapEnabledGlobal || fftEnabled) {
            int totalSamples = numFrames * 2; // stereo interleaved
            float[] pcm = new float[totalSamples];

            // Read from output buffer without disturbing its position
            int savedPos = outputBuffer.position();
            outputBuffer.order(ByteOrder.nativeOrder());

            if (encoding == C.ENCODING_PCM_FLOAT) {
                outputBuffer.asFloatBuffer().get(pcm);
            } else {
                // PCM_16BIT → float conversion
                for (int i = 0; i < totalSamples; i++) {
                    pcm[i] = outputBuffer.getShort() / 32768.0f;
                }
                outputBuffer.position(savedPos);
            }

            // ProjectM tap
            if (tapEnabledGlobal) {
                latestPcm.set(pcm);
            }

            // Push to C++ FFT ring buffer
            if (fftEnabled) {
                nativePushSamples(pcm, numFrames);
            }
        }
    }

    @Override
    protected void onFlush() {
        // Nothing to flush — we don't modify audio
    }

    @Override
    protected void onReset() {
        // Don't clear latestPcm — it's shared static state
    }

    // ---- ProjectM API (existing) ----

    public float[] getLatestPcm() {
        return latestPcm.getAndSet(null);
    }

    public void setTapEnabled(boolean enabled) {
        tapEnabledGlobal = enabled;
        if (!enabled) {
            latestPcm.set(null);
        }
        Log.d(TAG, "Tap " + (enabled ? "enabled" : "disabled"));
    }

    public boolean isTapEnabled() {
        return tapEnabledGlobal;
    }

    public int getSampleRate() {
        return sampleRate;
    }

    // ---- FFT Visualizer API (new) ----

    /**
     * Set the EventSink for FFT band data (64 floats, 0.0-1.0).
     * Called from EventChannel.StreamHandler in MainActivity.
     */
    public static void setFftSink(EventChannel.EventSink sink) {
        fftSink = sink;
        if (sink != null) {
            startFftVizThread();
        } else {
            stopFftVizThread();
        }
    }

    /**
     * Set the EventSink for waveform data (1024 bytes, 0-255).
     */
    public static void setWaveformSink(EventChannel.EventSink sink) {
        waveformSink = sink;
    }

    // Current frame interval in ms (default 33ms ≈ 30fps)
    private static long frameIntervalMs = 33;

    /**
     * Set the visualization frame rate (15-60 fps).
     * Restarts the viz thread with the new interval.
     */
    public static void setFrameRate(int fps) {
        fps = Math.max(15, Math.min(60, fps));
        frameIntervalMs = 1000 / fps;
        // Restart thread if running to apply new rate
        if (vizThread != null) {
            stopFftVizThread();
            startFftVizThread();
        }
        Log.d(TAG, "FFT viz frame rate set to " + fps + " fps (" + frameIntervalMs + "ms)");
    }

    /**
     * Set attack/decay smoothing rates for the C++ FFT bands.
     * @param attack 0.1 (smooth) to 0.9 (snappy) — how fast bands rise
     * @param decay  0.05 (slow) to 0.5 (fast) — how fast bands fall
     */
    public static void setSmoothing(float attack, float decay) {
        nativeSetSmoothing(attack, decay);
    }

    /**
     * Set gain / beat sensitivity for the FFT output.
     * @param gain 0.5 (subtle) to 3.0 (intense)
     */
    public static void setGain(float gain) {
        nativeSetGain(gain);
    }

    private static void startFftVizThread() {
        if (vizThread != null) return;
        fftEnabled = true;
        nativeInitFFT();

        vizThread = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "HypeFFTViz");
            t.setPriority(Thread.MIN_PRIORITY);
            return t;
        });

        vizThread.scheduleAtFixedRate(() -> {
            try {
                // Compute FFT bands in C++
                float[] bands = nativeComputeBands();
                if (bands != null && fftSink != null) {
                    mainHandler.post(() -> {
                        try {
                            if (fftSink != null) fftSink.success(bands);
                        } catch (Exception ignored) {}
                    });
                }

                // Also send waveform if listener is active
                byte[] waveform = nativeGetWaveform();
                if (waveform != null && waveformSink != null) {
                    mainHandler.post(() -> {
                        try {
                            if (waveformSink != null) waveformSink.success(waveform);
                        } catch (Exception ignored) {}
                    });
                }
            } catch (Exception e) {
                Log.w(TAG, "FFT viz tick error: " + e.getMessage());
            }
        }, 0, frameIntervalMs, TimeUnit.MILLISECONDS);

        Log.i(TAG, "FFT viz thread started at " + (1000 / frameIntervalMs) + " fps");
    }

    private static void stopFftVizThread() {
        fftEnabled = false;
        if (vizThread != null) {
            vizThread.shutdown();
            vizThread = null;
        }
        nativeDestroyFFT();
        Log.i(TAG, "FFT viz thread stopped");
    }
}
