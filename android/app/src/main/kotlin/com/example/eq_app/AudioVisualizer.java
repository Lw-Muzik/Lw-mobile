package com.example.eq_app;
import android.media.audiofx.Visualizer;

public class AudioVisualizer {

    private Visualizer visualizer;
    public static AudioVisualizer instance = new AudioVisualizer();

    public boolean isActive() {
        return visualizer != null;
    }

    public void activate(Visualizer.OnDataCaptureListener listener, int audioSessionId) {
        // try{
        visualizer = new Visualizer(audioSessionId);
        visualizer.setCaptureSize(Visualizer.getCaptureSizeRange()[1]);
        // visualizer.setMeasurementMode(Visualizer.MEASUREMENT_MODE_PEAK_RMS);
        // visualizer.setScalingMode(Visualizer.SCALING_MODE_AS_PLAYED);
        visualizer.setDataCaptureListener(
                listener,
                Visualizer.getMaxCaptureRate()/2,
                true,
                true);
        

    }
    public void scaleVisualizer(int scale){
        visualizer.setScalingMode(scale); // SCALING_MODE_NORMALIZED SCALING_MODE_AS_PLAYED
    }
    public int getAudioFreq(byte[] b) {
        return visualizer.getFft(b);
    }
    public void enableVisual(boolean enable){
        visualizer.setEnabled(enable);
    }
    public boolean isEnabled(){
        return visualizer.getEnabled();
    }
    public void deactivate() {
        visualizer.release();
    }

}
