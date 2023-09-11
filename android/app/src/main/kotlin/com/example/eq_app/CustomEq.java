package com.example.eq_app;

import android.media.audiofx.Equalizer;


import java.util.ArrayList;

public class CustomEq {
	private static final int m = Integer.MAX_VALUE;
	private static Equalizer equalizer;

	public static void init(int sessionId) {
		if(equalizer == null){
			equalizer = new Equalizer(m,0);
		}
	}

	public static void enable(boolean enable) {
		if (equalizer != null){
			// equalizer.release();
			equalizer.setEnabled(enable);
		}
	}
	public static boolean isEnabled() {
		if (equalizer != null)
			return equalizer.getEnabled();
		return false;
	}

	public static void setSettings(int bands) {

		StringBuilder bLevel = new StringBuilder("band1Level=0;");
		for (int i = 1; i < bands; i++) {
			bLevel.append("band").append(i + 1).append("Level=0;");
		}
		if (equalizer != null)
			equalizer.setProperties(new Equalizer.Settings("Equalizer;curPreset=-1;numBands="+bands+";"+bLevel));
	}
	public static String getSettings() {
		if (equalizer != null)
			return equalizer.getProperties().toString();
		return null;
	}

	public static ArrayList<Integer> getBandLevelRange() {
		ArrayList<Integer> bandLevels = new ArrayList<>();
		if(equalizer != null){
			short[] bandLevelRange = equalizer.getBandLevelRange();
			bandLevels.add(bandLevelRange[0] / 100);
			bandLevels.add(bandLevelRange[1] / 100);
			return bandLevels;
		}
		return bandLevels;
	}

	public static int getBandLevel(int bandId) {
		if(equalizer != null)
		  return equalizer.getBandLevel((short)bandId) / 100;
		return 0;
	}

	public static void setBandLevel(int bandId, int level) {
		if(equalizer != null){
			equalizer.setBandLevel((short)bandId, (short)level);
		}

	}

	public static ArrayList<Integer> getCenterBandFreqs() {
		ArrayList<Integer> bands = new ArrayList<>();
		if(equalizer != null){
			int n = equalizer.getNumberOfBands();
			for (int i = 0; i < n; i++) {
				bands.add(equalizer.getCenterFreq((short)i));
			}
			return bands;
		}

		return bands;
	}

	public static ArrayList<String> getPresetNames() {
		ArrayList<String> presets = new ArrayList<>();
		if(equalizer != null){
			short numberOfPresets = equalizer.getNumberOfPresets();

			for (int i = 0; i < numberOfPresets; i++) {
				presets.add(equalizer.getPresetName((short)i));
			}
			return presets;
		}
		return presets;
	}

	public static void setPreset(String presetName) {
		equalizer.usePreset((short)getPresetNames().indexOf(presetName));
	}
}