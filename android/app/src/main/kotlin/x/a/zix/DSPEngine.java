package x.a.zix;

import android.media.AudioManager;
import android.media.audiofx.DynamicsProcessing;
import android.os.Build;
import android.util.Log;

import androidx.annotation.RequiresApi;

@RequiresApi(api = Build.VERSION_CODES.P)
public class DSPEngine {
    private static DynamicsProcessing dspEngine;
    private static DynamicsProcessing.Eq dspEq;
    private static DynamicsProcessing.Eq tuner;
    private static final int bandCount = 10;
    private static DynamicsProcessing.Mbc dspMbc;
    static int[] dsp_speakers = {31, 62, 125, 250, 916, 1000, 2000, 4000, 8000, 16000};
    static float[] dsp_gains = {5.8f,1.6f,1.0f,5.0f,5,3,5,8,4,7};
    private static DynamicsProcessing.Limiter dspLimiter;

    private static DynamicsProcessing.MbcBand dspBand;
    public static final int priority = Integer.MAX_VALUE;
    private static final float out_gain = 3.0f;
    private static final float dsp_volume = -6.0f;
    private static final float dsp_powerBass = 8.0f;
    private static final float dsp_xBass = 11.0f;
    private static final float dsp_xBass2 = 10.0f;
    private static final float dsp_treble = 3.3f;
    static int audioSessionId = 0;
    static int tunerBassFreq = 916;

  private static final DynamicsProcessing.Config.Builder builder =  new DynamicsProcessing.Config.Builder(0, 2, true, bandCount, true, bandCount, true, bandCount, true);

   private static final DynamicsProcessing.Config engineConfig  = builder.build();
    
    // utility functions
    public static void setDspSpeakers(int[] speakers, float[] gains){
        dsp_speakers = speakers;
        dsp_gains = gains;

        if(dspEngine != null && dspEq != null){
            for (int b = 0; b < bandCount; b++) {
                try {
                    dspEq.getBand(b).setCutoffFrequency(dsp_speakers[b]);
                    dspMbc.getBand(b).setCutoffFrequency(dsp_speakers[b]);
                } catch (Exception e2) {
                    e2.printStackTrace();
                }
            }
            dspEngine.setPreEqAllChannelsTo(dspEq);
            dspEngine.setPostEqAllChannelsTo(dspEq);
//            dspEngine.setPreEqAllChannelsTo(tuner);
//            dspEngine.setPostEqAllChannelsTo(tuner);
            dspEngine.setMbcAllChannelsTo(dspMbc);
            dspEngine.setLimiterAllChannelsTo(dspLimiter);
        }

    }
    public static void setAudioSessionId(int id){
      audioSessionId = id;
    }
    public static void setCutOffFrequencyForTunerBass(int frequency){
        tunerBassFreq = frequency;
    }
    public static void assignBandGains() {
        for (int i = 0; i < bandCount; i++) {
            dspBandConfig(i, dsp_gains[i]);
        }
    }
    private static void presetOne() {
        if (Build.VERSION.SDK_INT < 28) {
            return;
        }
        for(int x = 0; x< 10; x++){
            DynamicsProcessing.MbcBand band  = dspMbc.getBand(x);
            dspBand = band;
            band.setAttackTime(10.0f);
            dspBand.setReleaseTime(100.0f);
            dspBand.setRatio(8.0f);
            dspBand.setKneeWidth(0.4f);
            dspBand.setThreshold(0.0f);
            dspBand.setNoiseGateThreshold(-90.0f);
            dspBand.setExpanderRatio(15.0f);
            dspBand.setPreGain(20.0f);
            dspBand.setPostGain(-4.0f);
            dspBand.setEnabled(true);
        }

    }
    private static void c() {
        if (Build.VERSION.SDK_INT < 28 || dspEngine == null) {
            return;
        }
        for (int i = 0; i < 1; i++) {
            DynamicsProcessing.MbcBand band = dspMbc.getBand(i);
            dspBand = band;
            band.setAttackTime(10.0f);
            dspBand.setReleaseTime(100.0f);
            dspBand.setRatio(8.0f);
            dspBand.setKneeWidth(0.4f);
            dspBand.setThreshold(0.0f);
            dspBand.setNoiseGateThreshold(-30.0f);
            dspBand.setExpanderRatio(15.0f);
            dspBand.setPreGain(20.0f);
            dspBand.setPostGain(0.0f);
        }
        dspBand.setEnabled(true);
    }

    public static void initDSPEngine() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            if(dspEngine == null){
                dspEngine = new DynamicsProcessing(priority, AudioManager.AUDIO_SESSION_ID_GENERATE, engineConfig);
                builder.setPreferredFrameDuration(10.0f);

                dspEq = new DynamicsProcessing.Eq(true, true, bandCount);
//                tuner = new DynamicsProcessing.Eq(true, true, 2);

                dspMbc = new DynamicsProcessing.Mbc(true, true, bandCount);
                //   Engine configuration
                dspLimiter = new DynamicsProcessing.Limiter(true, true, 7, 1.0f, 60.0f, 10.0f, -2.0f, out_gain);
                //  default chanel gain
                presetOne();
                c();
                // assign gain default gain values
                assignBandGains();
                // initialize dsp defaults
                dspEngine.setInputGainAllChannelsTo(dsp_volume);
                tunerConfig(0.0f,0);
                tunerConfig(0.0f,1);
                dspBandConfig(0, dsp_xBass);
                dspBandConfig(1, dsp_powerBass);
                dspBandConfig(2, dsp_xBass2);
                dspBandConfig(4, out_gain);
                dspBandConfig(9, dsp_treble);
            }

            dspEq.getBand(4).setCutoffFrequency(500);
            setDspSpeakers(dsp_speakers, dsp_gains);
// set tuner frequencies
//tuner.getBand(0).setCutoffFrequency(50);
//tuner.getBand(1).setCutoffFrequency(450);
         // assign frequencies to the bands
                for (int b = 0; b < bandCount; b++) {
                    try {
                        dspEq.getBand(b).setCutoffFrequency(dsp_speakers[b]);
                        dspMbc.getBand(b).setCutoffFrequency(dsp_speakers[b]);
                    } catch (Exception e2) {
                        e2.printStackTrace();
                    }
                }
            //    assign configurations globally
            dspEngine.setPreEqAllChannelsTo(dspEq);
            dspEngine.setPostEqAllChannelsTo(dspEq);
//            dspEngine.setPreEqAllChannelsTo(tuner);
//            dspEngine.setPostEqAllChannelsTo(tuner);
            dspEngine.setMbcAllChannelsTo(dspMbc);
            dspEngine.setLimiterAllChannelsTo(dspLimiter);

        }
    }
    public static void setNoiseThreshold(float noiseThreshold){
        if(dspBand != null){
            dspBand.setNoiseGateThreshold(noiseThreshold);
        }
    }


//    enable the DSP Engine
    public static void enableEngine(boolean enable) {

        if(dspEngine != null){
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                dspEngine.setEnabled(enable);
                dspEq.setEnabled(enable);
//                tuner.setEnabled(enable);
                dspMbc.setEnabled(enable);
                dspLimiter.setEnabled(enable);
          }
        }
    }
    private static void tunerConfig(float gain,int band){
        if(Build.VERSION.SDK_INT >= 28 && dspEngine != null && tuner != null){
            try {
               tuner.getBand(band).setGain(gain);
                dspEngine.setPreEqBandAllChannelsTo(band, tuner.getBand(band));
                dspEngine.setPostEqBandAllChannelsTo(band, tuner.getBand(band));
            } catch (Exception e2) {
                Log.e("TAGF", "setBandGain_Exception2!");
                e2.printStackTrace();
            }
        }
    }
    public static float getVocalLevel(){
        if(dspEq != null){
            return dspEq.getBand(4).getGain();
        }
        return 0;
    }
//    function to handle bandConfig
     private static void dspBandConfig(int band, float gain) {
        if (Build.VERSION.SDK_INT >= 28 && dspEngine != null && dspEq != null) {
                try {
                    dspEq.getBand(band).setGain(gain);
                    dspEngine.setPreEqBandAllChannelsTo(band, dspEq.getBand(band));
                    dspEngine.setPostEqBandAllChannelsTo(band, dspEq.getBand(band));
                } catch (UnsupportedOperationException e2) {
                        Log.e("TAGF", "setBandGain_Exception2!");
                    e2.printStackTrace();
                }
        }
    }

//    ------------------ setting dsp compressor- --------------------------
    public static void setOutGain(float gain) {
        initDSPEngine();
        if(dspEngine != null) {
            initDSPEngine();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                try {
                    dspLimiter.setPostGain(gain);
//                    dspBandConfig(4,gain);
                } catch (Exception ex) {
                    ex.printStackTrace();
                }

            }
        }
    }

    public static float getGainValue(){
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && dspEngine != null ) {
            initDSPEngine();
            return dspLimiter.getPostGain();
        }
        return 0.0f;
    }
//    function for audio threshold
    public static void setAudioThreshold(float threshold){
        initDSPEngine();
        if(dspEngine != null){
            dspLimiter.setThreshold(threshold);
        }
    }

    public static void setRelease(float knee){
        initDSPEngine();
        if(dspEngine != null){
            dspLimiter.setReleaseTime(knee);
        }
    }
    public static void setAttackTime(float knee){
        initDSPEngine();
        if(dspEngine != null){
            dspLimiter.setAttackTime(knee);
        }
    }
    public static void setAudioRatio(float ratio){
        if(dspEngine != null){
            dspLimiter.setRatio(ratio);
        }
    }

    public static void setKneeWidth(float knee){
        initDSPEngine();
        if(dspEngine != null){
            dspBand.setKneeWidth(knee);
        }
    }
//    function to adjust pre gain
    public static void setPreGain(float gain){
        initDSPEngine();
        if(dspEngine != null){
            dspBand.setPreGain(gain);
        }
    }
//    setExpanderRatio
    public static void setExpanderRatio(float ratio){
        initDSPEngine();
        if(dspEngine != null){
            dspBand.setRatio(ratio);
        }
    }
//    --------------- end of compresseor settings ----------------------------

    //  --------------- dsp power settings -----------------------
    public static void setDSPPowerBass(float gain){
        if(dspEngine != null){
            initDSPEngine();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                dspBandConfig(1,gain);
            }
        }
    }

    public static void setDSPXBass(float gain){
        if(dspEngine != null){
            initDSPEngine();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                dspBandConfig(0,gain);
            }
        }
    }

    public static void setDSPx(float gain){
        if(Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && dspEngine != null){
                dspBandConfig(2,gain);
        }
    }

    public static void setDSPVolume(float dsfxVolume) {
        initDSPEngine();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {

            dspEngine.setInputGainAllChannelsTo(dsfxVolume);
        }
    }
    public static void setDSPTreble(float gain){
        initDSPEngine();
        if(dspEngine != null){

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                dspBandConfig(9,gain);
            }
        }
    }
    public static void dispose(){
        if (dspEngine != null) {
            dspEngine.setEnabled(false);
            dspEngine.release();
            dspEngine = null;

        }
    }

//    tunner setting
    public static void setFrequencyForBassTuner(float bass){
        initDSPEngine();
        if(dspEngine != null){
            tuner.getBand(0).setCutoffFrequency(bass);
        }
    }

    public static void setFrequencyTrebleForTuner(float treble){
        initDSPEngine();
        if(dspEngine != null){
            tuner.getBand(1).setCutoffFrequency(treble);
        }
    }
    public static void setBassTone(float bass){
        initDSPEngine();
        if(dspEngine != null) {
//           tunerConfig(bass,0);
        }
    }

    public static void adjustTunerVocal(float gain){
        if(dspEq != null){
            dspBandConfig(4,gain);
        }

    }

}

//