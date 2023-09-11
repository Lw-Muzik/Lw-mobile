package com.example.eq_app;

import android.media.audiofx.EnvironmentalReverb;

public class ReverbControl {
    private static EnvironmentalReverb environmentalReverb;
    private static final int m = Integer.MAX_VALUE;
    public static void init(int sessionId) {
        environmentalReverb = new EnvironmentalReverb(m, sessionId);
    }

    public static void enable(boolean enable) {
        if (environmentalReverb != null){
            environmentalReverb.setEnabled(enable);
        }
            
    }

    public static boolean isEnabled() {
        if (environmentalReverb != null){
            return environmentalReverb.getEnabled();
        }
        return false;
    }

    public static void setDecayTime(int decayTime) {
        if (environmentalReverb != null)
            environmentalReverb.setDecayTime(decayTime);
    }

    public static int getDecayTime() {
        if (environmentalReverb != null)
            return environmentalReverb.getDecayTime();
        return 0;
    }

    public static void setDensity(int density) {
        if (environmentalReverb != null)
            environmentalReverb.setDensity((short)density);
    }

    public static int getDensity() {
        if (environmentalReverb != null)
            return ((int)environmentalReverb.getDensity());
        return 0;
    }

    public static void setDiffusion(int diffusion) {
        if (environmentalReverb != null)
            environmentalReverb.setDiffusion((short)diffusion);
    }

    public static int getDiffusion() {
        if (environmentalReverb != null)
            return ((int)environmentalReverb.getDiffusion());
        return 0;
    }

    public static void setReflectionsDelay(int reflectionsDelay) {
        if (environmentalReverb != null)
            environmentalReverb.setReflectionsDelay(reflectionsDelay);
    }

    public static int getReflectionsDelay() {
        if (environmentalReverb != null)
            return environmentalReverb.getReflectionsDelay();
        return 0;
    }

    public static void setReflectionsLevel(int reflectionsLevel) {
        if (environmentalReverb != null)
            environmentalReverb.setReflectionsLevel(((short)reflectionsLevel));
    }

    public static int getReflectionsLevel() {
        if (environmentalReverb != null)
            return ((int)environmentalReverb.getReflectionsLevel());
        return 0;
    }

    public static void setReverbDelay(int reverbDelay) {
        if (environmentalReverb != null)
            environmentalReverb.setReverbDelay(reverbDelay);
    }

    public static int getReverbDelay() {
        if (environmentalReverb != null)
            return environmentalReverb.getReverbDelay();
        return 0;
    }

    public static void setReverbLevel(int reverbLevel) {
        if (environmentalReverb != null)
            environmentalReverb.setReverbLevel((short)reverbLevel);
    }

    public static int getReverbLevel() {
        if (environmentalReverb != null)
            return environmentalReverb.getReverbLevel();
        return 0;
    }

    public static void setRoomHFLevel(int roomHFLevel) {
        if (environmentalReverb != null)
            environmentalReverb.setRoomHFLevel((short)roomHFLevel);
    }

    public static int getRoomHFLevel() {
        if (environmentalReverb != null)
            return ((int)environmentalReverb.getRoomHFLevel());
        return 0;
    }

    public static void setRoomLevel(int roomLevel) {
        if (environmentalReverb != null)
            environmentalReverb.setRoomLevel(((short)roomLevel));
    }

    public static int getRoomLevel() {
        if (environmentalReverb != null)
            return ((int)environmentalReverb.getRoomLevel());
        return 0;
    }

    public static void setDecayHFRatioLevel(int decayHFRatio) {
        if (environmentalReverb != null)
            environmentalReverb.setDecayHFRatio(((short)decayHFRatio));
    }

    public static int getDecayHFRatio() {
        if (environmentalReverb != null)
            return ((int)environmentalReverb.getDecayHFRatio());
        return 0;
    }
    public static int getReflectionsDelayLevel() {
        if (environmentalReverb != null)
            return environmentalReverb.getReflectionsDelay();
        return 0;
    }
    public static void setProperties(EnvironmentalReverb.Settings settings) {
        if (environmentalReverb != null)
            environmentalReverb.setProperties(settings);
    }

    public static EnvironmentalReverb.Settings getProperties() {
        if (environmentalReverb != null)
            return environmentalReverb.getProperties();
        return null;
    }

    public static void release() {
        if (environmentalReverb != null) {
            environmentalReverb.release();
            environmentalReverb = null;
        }
    }
}
