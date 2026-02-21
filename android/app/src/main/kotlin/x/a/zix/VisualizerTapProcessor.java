package x.a.zix;

import android.util.Log;
import androidx.annotation.NonNull;
import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.audio.BaseAudioProcessor;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Media3 AudioProcessor that taps PCM audio for visualization (projectM).
 * Passes audio through unchanged — only copies data to a shared AtomicReference
 * for lock-free consumption by the projectM render thread.
 *
 * Each ExoPlayer gets its own instance via {@link #createPlayerInstance()} for
 * independent buffer management (critical during crossfade). The PCM tap data
 * is shared across instances via a static AtomicReference.
 */
public class VisualizerTapProcessor extends BaseAudioProcessor {
    private static final String TAG = "VisualizerTap";

    // All player-attached instances
    private static final CopyOnWriteArrayList<VisualizerTapProcessor> playerInstances =
            new CopyOnWriteArrayList<>();

    // Shared PCM buffer across all instances — render thread reads from here
    private static final AtomicReference<float[]> latestPcm = new AtomicReference<>(null);

    // Shared tap state — broadcast to all instances
    private static volatile boolean tapEnabledGlobal = false;

    // Singleton kept for ProjectMRenderer to call getLatestPcm() / setTapEnabled()
    private static VisualizerTapProcessor singleton;

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

        // If tap is enabled, copy PCM data for projectM render thread
        if (tapEnabledGlobal) {
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

            latestPcm.set(pcm);
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

    // ---- Public API ----

    /**
     * Get the latest PCM snapshot. Returns null if no data available.
     * Called from projectM render thread — lock-free via AtomicReference.
     */
    public float[] getLatestPcm() {
        return latestPcm.getAndSet(null);
    }

    /** Enable/disable PCM tap. Broadcasts to all player instances. */
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
}
