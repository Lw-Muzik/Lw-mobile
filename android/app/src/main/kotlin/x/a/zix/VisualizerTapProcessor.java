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
     * True when the in-pipeline PCM tap is capturing — either the FFT/Flutter
     * visualizer path or the projectM tap. Used to keep the legacy Android
     * {@link android.media.audiofx.Visualizer} from running at the same time
     * (single active capture path; the custom tap is primary).
     */
    public static boolean isCustomTapActive() {
        return fftEnabled || tapEnabledGlobal;
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

    // Double-buffered PCM scratch (F7): eliminates the per-callback heap
    // allocation and keeps the projectM reader thread-safe. Each callback fills
    // the buffer the reader is NOT currently holding, so we never mutate an
    // array that getLatestPcm() may have handed out. Per-instance (each player
    // has its own audio thread), so no cross-instance contention.
    private float[] pcmBufA;
    private float[] pcmBufB;
    private boolean pcmToggle = false;
    // Reusable staging buffer for bulk PCM_16 -> float conversion (grow-only).
    private short[] shortScratch;

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

            // Fill the buffer the projectM reader is NOT holding (double-buffer).
            // Reallocate only when the frame count actually changes (rare, e.g.
            // a format switch) — steady-state playback reuses the arrays with
            // zero allocation on the audio thread. Exact sizing is required:
            // projectM consumes the whole array by length, and the bulk
            // FloatBuffer.get(array) reads exactly array.length samples.
            float[] pcm = pcmToggle ? pcmBufA : pcmBufB;
            if (pcm == null || pcm.length != totalSamples) {
                pcm = new float[totalSamples];
                if (pcmToggle) pcmBufA = pcm; else pcmBufB = pcm;
            }

            // Read a copy without disturbing the output buffer's position:
            // asShortBuffer()/asFloatBuffer() views start at the current
            // position and never advance the parent buffer.
            outputBuffer.order(ByteOrder.nativeOrder());

            if (encoding == C.ENCODING_PCM_FLOAT) {
                outputBuffer.asFloatBuffer().get(pcm);
            } else {
                // Bulk PCM_16BIT → float. Identical scaling to the previous
                // per-sample getShort() / 32768.0f, but with one bulk copy
                // instead of N bounds-checked ByteBuffer.getShort() calls.
                if (shortScratch == null || shortScratch.length < totalSamples) {
                    shortScratch = new short[totalSamples];
                }
                outputBuffer.asShortBuffer().get(shortScratch, 0, totalSamples);
                for (int i = 0; i < totalSamples; i++) {
                    pcm[i] = shortScratch[i] / 32768.0f;
                }
            }

            // ProjectM tap
            if (tapEnabledGlobal) {
                latestPcm.set(pcm);
            }

            // Push to C++ FFT ring buffer (synchronous copy — length-agnostic)
            if (fftEnabled) {
                nativePushSamples(pcm, numFrames);
            }

            // Flip so the next callback writes the other buffer, giving any
            // reader a full callback period before this array is reused.
            pcmToggle = !pcmToggle;
        }
    }

    @Override
    protected void onFlush() {
        // Re-register if a prior onReset() removed this instance mid-life
        // (media3 can reset a still-live processor during setAudioSource
        // reconfiguration). CopyOnWriteArrayList makes contains()/add() safe.
        if (!playerInstances.contains(this)) {
            playerInstances.add(this);
        }
    }

    @Override
    protected void onReset() {
        // Prune this instance so the static list doesn't grow unbounded across
        // crossfade/stop-start cycles (just_audio disposes and recreates the
        // platform player, which reset()s each processor). onFlush() re-adds
        // it if media3 flushes this same instance again (mid-life reset).
        playerInstances.remove(this);
        // Release the per-instance PCM scratch buffers; queueInput reallocates
        // them on demand (guarded by a null/length check) if this instance is
        // ever reused. Don't clear latestPcm — it's shared static state.
        pcmBufA = null;
        pcmBufB = null;
        shortScratch = null;
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
        // The custom in-pipeline tap is primary: stop the legacy Android
        // Visualizer if it's running so only one PCM capture path is active.
        try {
            AudioVisualizer legacy = AudioVisualizer.getInstance();
            if (legacy.isActive()) {
                legacy.deactivate();
                Log.i(TAG, "Deactivated legacy Visualizer — custom FFT tap is primary");
            }
        } catch (Exception ignored) {}
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
        // Order matters (teardown race, use-after-free):
        //  1. Clear fftEnabled FIRST so the audio thread stops calling
        //     nativePushSamples and the viz tick stops after its current pass.
        //  2. Wait for any in-flight viz tick (which may be inside
        //     nativeComputeBands / nativeGetWaveform) to finish before
        //     nativeDestroyFFT() frees the native FFT object. The C++ side
        //     also guards g_fftViz with a mutex to close the audio-thread
        //     window, but draining the viz executor here avoids the wait.
        fftEnabled = false;
        if (vizThread != null) {
            vizThread.shutdown();
            try {
                vizThread.awaitTermination(500, TimeUnit.MILLISECONDS);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            vizThread = null;
        }
        nativeDestroyFFT();
        Log.i(TAG, "FFT viz thread stopped");
    }
}
