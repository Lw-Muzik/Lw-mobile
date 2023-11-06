package x.a.zix;

import android.annotation.SuppressLint;
import android.media.audiofx.Visualizer;
import android.media.AudioManager;

public class AudioVisualizer {

    private Visualizer visualizer;
    private boolean isActive = false;
    public static AudioVisualizer instance = new AudioVisualizer();

    public boolean isActive() {
        return isActive;
    }

    @SuppressLint("NewApi")
    public void activate(Visualizer.OnDataCaptureListener listener) {
        if (visualizer == null) {
            visualizer = new Visualizer(AudioManager.AUDIO_SESSION_ID_GENERATE);
            visualizer.setEnabled(true);
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

    @SuppressLint("NewApi")
    public void setScalingMode(boolean isNormalized) {
        if (visualizer != null) {
            visualizer.setScalingMode(isNormalized ? Visualizer.SCALING_MODE_NORMALIZED : Visualizer.SCALING_MODE_AS_PLAYED);
        }
    }

    @SuppressLint("NewApi")
    public int getAudioFreq(byte[] b) {
        return visualizer.getFft(b);
    }

    @SuppressLint("NewApi")
    public void enableVisual(boolean enable) {
        if (visualizer != null) {
            visualizer.setEnabled(enable);
        }
    }

    @SuppressLint("NewApi")
    public boolean isEnabled() {
        return visualizer != null && visualizer.getEnabled();
    }

    @SuppressLint("NewApi")
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
//        this.frameRate = frameRate;
    }
}
