package x.a.zix;

import android.annotation.SuppressLint;
import android.media.AudioManager;
import android.media.audiofx.Visualizer;
import android.util.Log;

public class AudioVisualizer {
    private static final String TAG = "AudioVisualizer";
    private Visualizer visualizer;
    private boolean isActive = false;
    private static final int CAPTURE_SIZE = 1024; // Must be a power of 2
    private int audioSessionId = AudioManager.AUDIO_SESSION_ID_GENERATE;
    
    // Singleton pattern with private constructor
    private static AudioVisualizer instance;
    
    private AudioVisualizer() {
        // Private constructor to enforce singleton pattern
    }
    
    public static synchronized AudioVisualizer getInstance() {
        if (instance == null) {
            instance = new AudioVisualizer();
        }
        return instance;
    }

    public boolean isActive() {
        return isActive;
    }

    @SuppressLint("NewApi")
    public void activate(Visualizer.OnDataCaptureListener listener) {
        // First, clean up any existing visualizer
        deactivate();
        try {
            visualizer = new Visualizer(audioSessionId);
//            currentAudioSessionId = audioSessionId;
            
            // Check if we can get a valid capture size range
            int[] range = Visualizer.getCaptureSizeRange();
            if (range != null) {
                // Use CAPTURE_SIZE if it's within the valid range, otherwise use the maximum
                int captureSize = Math.min(CAPTURE_SIZE, range[1]);
                visualizer.setCaptureSize(captureSize);
            } else {
                Log.e(TAG, "Failed to get capture size range");
                return;
            }
            visualizer.setScalingMode(Visualizer.SCALING_MODE_NORMALIZED);
            // Set the data capture listener
            visualizer.setDataCaptureListener(
                listener,
                Visualizer.getMaxCaptureRate() / 2, // Use half of max rate for better performance
                true,  // Enable waveform capture
                true   // Enable FFT capture
            );

            // Enable the visualizer
            visualizer.setEnabled(true);
            isActive = true;
            
            Log.d(TAG, "Visualizer activated successfully for session: " + audioSessionId);
        } catch (Exception e) {
            Log.e(TAG, "Error activating visualizer: " + e.getMessage());
            e.printStackTrace();
            deactivate();
        }
    }

    @SuppressLint("NewApi")
    public void setScalingMode(boolean isNormalized) {
        if (visualizer != null && isActive) {
            try {
                visualizer.setScalingMode(
                    isNormalized ? 
                    Visualizer.SCALING_MODE_NORMALIZED : 
                    Visualizer.SCALING_MODE_AS_PLAYED
                );
            } catch (Exception e) {
                Log.e(TAG, "Error setting scaling mode: " + e.getMessage());
            }
        }
    }

    @SuppressLint("NewApi")
    public boolean getAudioData(byte[] waveform, byte[] fft) {
        if (visualizer != null && isActive && visualizer.getEnabled()) {
            try {
                return visualizer.getWaveForm(waveform) == Visualizer.SUCCESS &&
                       visualizer.getFft(fft) == Visualizer.SUCCESS;
            } catch (Exception e) {
                Log.e(TAG, "Error capturing audio data: " + e.getMessage());
                return false;
            }
        }
        return false;
    }

    @SuppressLint("NewApi")
    public void enableVisual(boolean enable) {
        if (visualizer != null) {
            try {
                visualizer.setEnabled(enable);
                isActive = enable;
            } catch (Exception e) {
                Log.e(TAG, "Error enabling visualizer: " + e.getMessage());
            }
        }
    }

    @SuppressLint("NewApi")
    public boolean isEnabled() {
        return visualizer != null && visualizer.getEnabled();
    }

    @SuppressLint("NewApi")
    public void deactivate() {
        if (visualizer != null) {
            try {
                visualizer.setEnabled(false);
                visualizer.release();
                visualizer = null;
                isActive = false;
//                currentAudioSessionId = -1;
                Log.d(TAG, "Visualizer deactivated successfully");
            } catch (Exception e) {
                Log.e(TAG, "Error deactivating visualizer: " + e.getMessage());
            }
        }
    }

    public int getCurrentAudioSessionId() {
        return audioSessionId;
    }
}