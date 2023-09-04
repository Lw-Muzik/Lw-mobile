package com.example.eq_app;

import android.media.audiofx.Equalizer;


import java.util.ArrayList;

public class CustomEq {
	private static Equalizer equalizer;

	public static void init(int sessionId) {
		equalizer = new Equalizer(0, sessionId);
	}

	public static void enable(boolean enable) {
		if (equalizer != null){
			if(enable == true){
				equalizer.setEnabled(enable);
			} else {
				equalizer.setEnabled(enable);
				// equalizer.release();
			}
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
		short[] bandLevelRange = equalizer.getBandLevelRange();
		ArrayList<Integer> bandLevels = new ArrayList<>();
		bandLevels.add(bandLevelRange[0] / 100);
		bandLevels.add(bandLevelRange[1] / 100);
		return bandLevels;
	}

	public static int getBandLevel(int bandId) {
		return equalizer.getBandLevel((short)bandId) / 100;
	}

	public static void setBandLevel(int bandId, int level) {
		equalizer.setBandLevel((short)bandId, (short)level);
	}

	public static ArrayList<Integer> getCenterBandFreqs() {
		int n = equalizer.getNumberOfBands();
		ArrayList<Integer> bands = new ArrayList<>();
		for (int i = 0; i < n; i++) {
			bands.add(equalizer.getCenterFreq((short)i));
		}
		return bands;
	}

	public static ArrayList<String> getPresetNames() {
		short numberOfPresets = equalizer.getNumberOfPresets();
		ArrayList<String> presets = new ArrayList<>();
		for (int i = 0; i < numberOfPresets; i++) {
			presets.add(equalizer.getPresetName((short)i));
		}
		return presets;
	}

	public static void setPreset(String presetName) {
		equalizer.usePreset((short)getPresetNames().indexOf(presetName));
	}
}