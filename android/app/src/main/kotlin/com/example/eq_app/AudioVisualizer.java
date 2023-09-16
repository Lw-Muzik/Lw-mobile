package com.example.eq_app;

import android.media.AudioManager;
import android.media.audiofx.Visualizer;


public class AudioVisualizer {

    private Visualizer visualizer;
    private boolean isActive = false;
    private boolean isScalingModeNormalized = true; // Default scaling mode
    private int frameRate = 2; // Default frame rate (adjust as needed)

    public static AudioVisualizer instance = new AudioVisualizer();

    public boolean isActive() {
        return isActive;
    }

    public void activate(Visualizer.OnDataCaptureListener listener, int audioSessionId) {
        if (visualizer == null) {
            visualizer = new Visualizer(AudioManager.AUDIO_SESSION_ID_GENERATE);
            visualizer.setCaptureSize(Visualizer.getCaptureSizeRange()[1]);
            visualizer.setDataCaptureListener(
                listener,
                Visualizer.getMaxCaptureRate() / 2,
                true,
                true
            );
            isActive = true;
        }
    }

    public void setScalingMode(boolean isNormalized) {
        if (visualizer != null) {
            visualizer.setScalingMode(isNormalized ? Visualizer.SCALING_MODE_NORMALIZED : Visualizer.SCALING_MODE_AS_PLAYED);
        }
    }

    public int getAudioFreq(byte[] b) {
        return visualizer.getFft(b);
    }

    public void enableVisual(boolean enable) {
        if (visualizer != null) {
            visualizer.setEnabled(enable);
        }
    }

    public boolean isEnabled() {
        return visualizer != null && visualizer.getEnabled();
    }

    public void deactivate() {
        if (visualizer != null) {
            visualizer.release();
            visualizer = null;
            isActive = false;
        }
    }

    public void setFrameRate(int frameRate) {
        // You can use this method to control the animation speed
        // Adjust the frameRate parameter to control the speed (e.g., 60 FPS)
        this.frameRate = frameRate;
    }
}
