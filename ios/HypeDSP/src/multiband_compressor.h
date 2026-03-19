#pragma once
#include "biquad.h"
#include "compressor.h"
#include <atomic>
#include <algorithm>
#include <cstring>

// 10-band multi-band compressor using Linkwitz-Riley 4th order crossovers.
//
// Architecture:
//   - 9 crossover points split audio into 10 frequency bands
//   - Each crossover is Linkwitz-Riley 4th order (24 dB/oct) = two cascaded
//     2nd-order Butterworth filters (lowpass and highpass)
//   - Linkwitz-Riley crossovers guarantee flat magnitude response at the
//     crossover frequency (both outputs are -6 dB, sum to 0 dB)
//   - Each band has an independent Compressor instance
//   - Bands are summed after compression for the output
//
// Crossover topology (sequential split):
//   Input -> LP0/HP0 at f0
//            LP0 = Band 0
//            HP0 -> LP1/HP1 at f1
//                   LP1 = Band 1
//                   HP1 -> LP2/HP2 at f2
//                          ...and so on
//
// This sequential topology ensures every crossover processes only the
// frequency content above the previous split point.

static constexpr int MBC_BAND_COUNT = 10;
static constexpr int MBC_CROSSOVER_COUNT = MBC_BAND_COUNT - 1; // 9

// Default MBC crossover frequencies (Hz) — matching the old DynamicsProcessing bands
static constexpr float MBC_DEFAULT_FREQUENCIES[MBC_BAND_COUNT] = {
    31.0f, 62.0f, 125.0f, 250.0f, 500.0f, 1000.0f, 2000.0f, 4000.0f, 8000.0f, 16000.0f
};

// Linkwitz-Riley 4th order crossover = two cascaded 2nd-order Butterworth.
// At the crossover frequency, both LP and HP are at -6 dB.
// LP^2 + HP^2 = 1 (power complementary).
struct LRCrossover {
    // Two cascaded biquads for lowpass
    Biquad lpStage1L, lpStage2L; // left channel
    Biquad lpStage1R, lpStage2R; // right channel
    // Two cascaded biquads for highpass
    Biquad hpStage1L, hpStage2L;
    Biquad hpStage1R, hpStage2R;

    void configure(float sampleRate, float freq) {
        // Butterworth Q = 0.7071 (1/sqrt(2)) for each 2nd-order stage
        constexpr float Q = 0.7071067811865476f;
        BiquadCoeffs lp = BiquadDesign::lowPass(sampleRate, freq, Q);
        BiquadCoeffs hp = BiquadDesign::highPass(sampleRate, freq, Q);
        // Set both stages to same coefficients (cascading = LR4)
        lpStage1L.setCoefficientsImmediate(lp);
        lpStage2L.setCoefficientsImmediate(lp);
        lpStage1R.setCoefficientsImmediate(lp);
        lpStage2R.setCoefficientsImmediate(lp);
        hpStage1L.setCoefficientsImmediate(hp);
        hpStage2L.setCoefficientsImmediate(hp);
        hpStage1R.setCoefficientsImmediate(hp);
        hpStage2R.setCoefficientsImmediate(hp);
    }

    void reset() {
        lpStage1L.reset(); lpStage2L.reset();
        lpStage1R.reset(); lpStage2R.reset();
        hpStage1L.reset(); hpStage2L.reset();
        hpStage1R.reset(); hpStage2R.reset();
    }

    // Process: splits input L/R into lowL/R and highL/R
    void process(const float* inL, const float* inR,
                 float* lowL, float* lowR,
                 float* highL, float* highR,
                 int numFrames) {
        // Copy input for both paths
        std::memcpy(lowL, inL, numFrames * sizeof(float));
        std::memcpy(lowR, inR, numFrames * sizeof(float));
        std::memcpy(highL, inL, numFrames * sizeof(float));
        std::memcpy(highR, inR, numFrames * sizeof(float));

        // Lowpass: two cascaded stages
        lpStage1L.process(lowL, lowR, numFrames);
        // Need separate R processing for stage 1 since Biquad processes L&R together
        lpStage2L.process(lowL, lowR, numFrames);

        // Highpass: two cascaded stages
        hpStage1L.process(highL, highR, numFrames);
        hpStage2L.process(highL, highR, numFrames);
    }
};

class MultibandCompressor {
public:
    MultibandCompressor() {
        enabled_.store(false);
    }

    void init(float sampleRate) {
        sampleRate_ = sampleRate;

        // Initialize crossovers at default frequencies
        // Crossover i sits between band i and band i+1
        // Crossover frequency = geometric mean of band centers
        for (int i = 0; i < MBC_CROSSOVER_COUNT; i++) {
            float freq = std::sqrt(MBC_DEFAULT_FREQUENCIES[i] *
                                    MBC_DEFAULT_FREQUENCIES[i + 1]);
            crossoverFreqs_[i] = freq;
            crossovers_[i].configure(sampleRate, freq);
        }

        // Initialize per-band compressors with defaults
        for (int i = 0; i < MBC_BAND_COUNT; i++) {
            compressors_[i].init(sampleRate);
            Compressor::Params p;
            p.threshold = -18.0f;
            p.ratio = 2.5f;
            p.kneeWidth = 8.0f;
            p.attackTime = 15.0f;
            p.releaseTime = 45.0f;
            p.noiseGateThreshold = -70.0f;
            p.expanderRatio = 2.0f;
            p.preGain = 0.0f;
            p.postGain = 0.0f;
            p.enabled = true;
            compressors_[i].setParams(p);
        }
    }

    void reinit(float sampleRate) {
        sampleRate_ = sampleRate;
        for (int i = 0; i < MBC_CROSSOVER_COUNT; i++) {
            crossovers_[i].configure(sampleRate, crossoverFreqs_[i]);
        }
        for (int i = 0; i < MBC_BAND_COUNT; i++) {
            compressors_[i].init(sampleRate);
        }
    }

    void reset() {
        for (int i = 0; i < MBC_CROSSOVER_COUNT; i++) {
            crossovers_[i].reset();
        }
        for (int i = 0; i < MBC_BAND_COUNT; i++) {
            compressors_[i].reset();
        }
    }

    // Process deinterleaved stereo in-place
    void process(float* left, float* right, int numFrames) {
        if (!enabled_.load(std::memory_order_relaxed)) return;
        if (numFrames <= 0) return;

        // Allocate band buffers (L + R per band) + highTemp (L + R)
        constexpr int STACK_LIMIT = 512;
        int bufSize = numFrames * 2 * (MBC_BAND_COUNT + 1); // +1 for highTemp
        float stackBuf[STACK_LIMIT * 2 * (MBC_BAND_COUNT + 1)];
        float* heapBuf = nullptr;
        float* bufBase;

        if (numFrames <= STACK_LIMIT) {
            bufBase = stackBuf;
        } else {
            heapBuf = new float[bufSize];
            bufBase = heapBuf;
        }

        // Per-band L/R pointers
        float* bandL[MBC_BAND_COUNT];
        float* bandR[MBC_BAND_COUNT];
        for (int b = 0; b < MBC_BAND_COUNT; b++) {
            bandL[b] = bufBase + b * numFrames * 2;
            bandR[b] = bandL[b] + numFrames;
        }
        // highTemp buffer for the remaining high-passed signal after each split
        float* highTempL = bufBase + MBC_BAND_COUNT * numFrames * 2;
        float* highTempR = highTempL + numFrames;

        // Sequential crossover splitting:
        //   Split input at f0 -> band[0] (low) + highTemp (high)
        //   Split highTemp at f1 -> band[1] (low) + highTemp (high)
        //   ...repeat...
        //   After last split, highTemp = band[9] (highest band)
        //
        // LRCrossover::process() copies input via memcpy BEFORE filtering,
        // so using highTemp as both input and highpass output is safe.

        // First split from the original input
        crossovers_[0].process(left, right,
                               bandL[0], bandR[0],
                               highTempL, highTempR,
                               numFrames);

        // Subsequent splits: each takes highTemp and splits again
        for (int i = 1; i < MBC_CROSSOVER_COUNT; i++) {
            crossovers_[i].process(highTempL, highTempR,
                                   bandL[i], bandR[i],
                                   highTempL, highTempR,
                                   numFrames);
        }

        // After the last crossover, highTemp holds the highest band
        std::memcpy(bandL[MBC_BAND_COUNT - 1], highTempL, numFrames * sizeof(float));
        std::memcpy(bandR[MBC_BAND_COUNT - 1], highTempR, numFrames * sizeof(float));

        // Compress each band independently
        for (int b = 0; b < MBC_BAND_COUNT; b++) {
            compressors_[b].process(bandL[b], bandR[b], numFrames);
        }

        // Sum all bands back to output
        for (int i = 0; i < numFrames; i++) {
            float sumL = 0.0f, sumR = 0.0f;
            for (int b = 0; b < MBC_BAND_COUNT; b++) {
                sumL += bandL[b][i];
                sumR += bandR[b][i];
            }
            left[i] = sumL;
            right[i] = sumR;
        }

        delete[] heapBuf;
    }

    // Global enable/disable
    void setEnabled(bool enabled) { enabled_.store(enabled); }
    bool isEnabled() const { return enabled_.load(); }

    // Set parameters on all bands uniformly
    void setAllThresholds(float dB) {
        for (int i = 0; i < MBC_BAND_COUNT; i++) compressors_[i].setThreshold(dB);
    }
    void setAllRatios(float r) {
        for (int i = 0; i < MBC_BAND_COUNT; i++) compressors_[i].setRatio(r);
    }
    void setAllKneeWidths(float dB) {
        for (int i = 0; i < MBC_BAND_COUNT; i++) compressors_[i].setKneeWidth(dB);
    }
    void setAllAttackTimes(float ms) {
        for (int i = 0; i < MBC_BAND_COUNT; i++) compressors_[i].setAttackTime(ms);
    }
    void setAllReleaseTimes(float ms) {
        for (int i = 0; i < MBC_BAND_COUNT; i++) compressors_[i].setReleaseTime(ms);
    }
    void setAllPreGains(float dB) {
        for (int i = 0; i < MBC_BAND_COUNT; i++) compressors_[i].setPreGain(dB);
    }
    void setAllPostGains(float dB) {
        for (int i = 0; i < MBC_BAND_COUNT; i++) compressors_[i].setPostGain(dB);
    }
    void setAllNoiseGateThresholds(float dB) {
        for (int i = 0; i < MBC_BAND_COUNT; i++) compressors_[i].setNoiseGateThreshold(dB);
    }
    void setAllExpanderRatios(float r) {
        for (int i = 0; i < MBC_BAND_COUNT; i++) compressors_[i].setExpanderRatio(r);
    }

    // Per-band compressor access
    Compressor& getBand(int band) { return compressors_[std::clamp(band, 0, MBC_BAND_COUNT - 1)]; }

private:
    float sampleRate_ = 48000.0f;
    float crossoverFreqs_[MBC_CROSSOVER_COUNT];
    LRCrossover crossovers_[MBC_CROSSOVER_COUNT];
    Compressor compressors_[MBC_BAND_COUNT];
    std::atomic<bool> enabled_{false};
};
