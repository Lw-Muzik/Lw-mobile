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
            try {
                int audioSessionId = AudioManager.AUDIO_SESSION_ID_GENERATE;
                visualizer = new Visualizer(audioSessionId);
                visualizer.setCaptureSize(Visualizer.getCaptureSizeRange()[1]); // Use maximum capture size
                
                visualizer.setDataCaptureListener(
                    listener,
                    Visualizer.getMaxCaptureRate(),
                    true,  // Enable waveform capture
                    true   // Enable FFT capture
                );
                if(visualizer != null){
                    visualizer.setEnabled(true);
                }

                isActive = true;
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }

    @SuppressLint("NewApi")
    public void setScalingMode(boolean isNormalized) {
        if (visualizer != null) {
            visualizer.setScalingMode(isNormalized ? Visualizer.SCALING_MODE_NORMALIZED : Visualizer.SCALING_MODE_AS_PLAYED);
        }
    }

    @SuppressLint("NewApi")
    public void getAudioData(byte[] waveform, byte[] fft) {
        if (visualizer != null) {
            visualizer.getWaveForm(waveform);
            visualizer.getFft(fft);
        }
    }

    @SuppressLint("NewApi")
    public void enableVisual(boolean enable) {
        if (visualizer != null) {
            visualizer.setEnabled(enable);
            isActive = enable;
        }
    }

    @SuppressLint("NewApi")
    public boolean isEnabled() {
        return visualizer != null && visualizer.getEnabled();
    }

    @SuppressLint("NewApi")
    public void deactivate() {
        if (visualizer != null) {
            visualizer.setEnabled(false);
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