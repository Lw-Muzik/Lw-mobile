package com.example.eq_app;

import android.media.audiofx.DynamicsProcessing;
import android.os.Build;
import android.util.Log;

import androidx.annotation.RequiresApi;

@RequiresApi(api = Build.VERSION_CODES.P)
public class DSPEngine {
    private static DynamicsProcessing dspEngine;
    private static DynamicsProcessing.Eq dspEq;
    private static final int bandCount = 10;
    private static DynamicsProcessing.Mbc dspMbc;
    static int[] dsp_speakers;
    static int[] dsp_gains;
    private static DynamicsProcessing.Limiter dspLimiter;
    private static final int[] bandFreq = {31, 62, 125, 250, 916, 1000, 2000, 4000, 8000, 16000};
    private static final int[] bandFreq2 = {75, 150, 250, 600, 1200, 2400, 4800, 9600, 8000, 19200};
    /**
     *
     *  iArr[0] = 8;
     *             iArr[1] = 8;
     *             iArr[2] = 1;
     *             iArr[3] = 1;
     *             iArr[4] = 5;
     *             iArr[5] = 3;
     *             iArr[6] = 5;
     *             iArr[7] = 8;
     *             iArr[8] = 8;
     *             iArr[9] = 9;
     */
    private static final int[] bandGain = {8,6,1,5,5,3,5,8,4,7};
    private static DynamicsProcessing.MbcBand dspBand;
    public static final int priority = Integer.MAX_VALUE;
    private static final float out_gain = 3.0f;
    private static final float dsp_volume = -8.0f;
    private static final float dsp_powerBass = 8.0f;
    private static final float dsp_xBass = 11.0f;
    private static final float dsp_xBass2 = 10.0f;
    private static final float dsp_treble = 3.3f;
    static int audioSessionId = 0;
    static DynamicsProcessing.Config.Builder builder =  new DynamicsProcessing.Config.Builder(0, 2, true, bandCount, true, bandCount, true, bandCount, false);

   static final DynamicsProcessing.Config engineConfig  = builder.build();
    
    // utility functions
    public static void setDspSpeakers(int[] speakers,int[] gains){
        dsp_speakers = speakers;
        dsp_gains = gains;
    }
    public static void setAudioSessionId(int id){
      audioSessionId = id;
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
            setDspSpeakers(bandFreq, bandGain);
            if(dspEngine == null){
                dspEngine = new DynamicsProcessing(priority,audioSessionId, engineConfig);
                builder.setPreferredFrameDuration(10.0f);

                dspEq = new DynamicsProcessing.Eq(true, true, bandCount);
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
                dspBandConfig(0, dsp_xBass);
                dspBandConfig(1, dsp_powerBass);
                dspBandConfig(2, dsp_xBass2);
                dspBandConfig(4, out_gain);
                dspBandConfig(9, dsp_treble);
            }
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
            dspEngine.setMbcAllChannelsTo(dspMbc);
            dspEngine.setLimiterAllChannelsTo(dspLimiter);
        }
    }
//    enable the DSP Engine
    public static void enableEngine(boolean enable) {
        if(dspEngine != null){

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            if (enable) {
                dspEngine.setEnabled(true);
                dspEq.setEnabled(true);
                dspMbc.setEnabled(true);
                dspLimiter.setEnabled(true);
             } else {
                    dspEngine.setEnabled(false);
                    dspMbc.setEnabled(false);
                    dspEq.setEnabled(false);
                    dspLimiter.setEnabled(false);
            }
          }
        }
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
    public static void setOutGain(float gain) {
        if(dspEngine != null){
            initDSPEngine();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                dspLimiter.getPostGain();
                 dspLimiter.setPostGain(gain);
                dspBandConfig(4,gain);
            }
        }


    }

    public static float getGainValue(){
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && dspEngine != null ) {
            initDSPEngine();
            return dspLimiter.getPostGain();
//            return dspEq.getBand(4).getGain();
        }
        return 0.0f;
    }
//    set Gain for all channels
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            initDSPEngine();
            dspEngine.setInputGainAllChannelsTo(dsfxVolume);
        }
    }
    public static void setDSPTreble(float gain){
        if(dspEngine != null){
            initDSPEngine();
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
}
