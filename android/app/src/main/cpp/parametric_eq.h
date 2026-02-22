#pragma once
#include "biquad.h"
#include <atomic>
#include <algorithm>

static constexpr int MAX_EQ_BANDS = 32;

// 32-band ISO 1/3-octave center frequencies (Hz)
static constexpr float ISO_FREQUENCIES[MAX_EQ_BANDS] = {
    20.0f, 25.0f, 31.5f, 40.0f, 50.0f, 63.0f, 80.0f, 100.0f,
    125.0f, 160.0f, 200.0f, 250.0f, 315.0f, 400.0f, 500.0f, 630.0f,
    800.0f, 1000.0f, 1250.0f, 1600.0f, 2000.0f, 2500.0f, 3150.0f, 4000.0f,
    5000.0f, 6300.0f, 8000.0f, 10000.0f, 12500.0f, 16000.0f, 18000.0f, 20000.0f
};

// Q for 1/3-octave graphic EQ bands (~4.318)
static constexpr float GRAPHIC_Q = 4.318f;

// Per-band parameters
struct EqBandParams {
    float frequency = 1000.0f;
    float gainDb = 0.0f;
    float q = GRAPHIC_Q;
    BiquadType type = BiquadType::Peaking;
    bool enabled = true;
};

// Multi-band parametric/graphic EQ.
// Manages up to MAX_EQ_BANDS biquad filters.
class ParametricEQ {
public:
    ParametricEQ() : numBands_(0), sampleRate_(48000.0f) {
        enabled_.store(true);
    }

    // Initialize with given band count, all flat
    void init(float sampleRate, int numBands) {
        sampleRate_ = sampleRate;
        numBands_ = std::min(numBands, MAX_EQ_BANDS);
        for (int i = 0; i < numBands_; i++) {
            params_[i] = EqBandParams();
            biquads_[i].reset();
        }
    }

    // Initialize as graphic EQ with fixed ISO 1/3-octave frequencies
    void initGraphic(float sampleRate, int numBands = MAX_EQ_BANDS) {
        sampleRate_ = sampleRate;
        numBands_ = std::min(numBands, MAX_EQ_BANDS);
        for (int i = 0; i < numBands_; i++) {
            params_[i].frequency = ISO_FREQUENCIES[i];
            params_[i].gainDb = 0.0f;
            params_[i].q = GRAPHIC_Q;
            params_[i].type = BiquadType::Peaking;
            params_[i].enabled = true;
            biquads_[i].reset();
        }
    }

    // Reinitialize at new sample rate, preserving current params
    void reinit(float sampleRate) {
        sampleRate_ = sampleRate;
        for (int i = 0; i < numBands_; i++) {
            biquads_[i].reset();
            if (std::fabs(params_[i].gainDb) > 0.05f && params_[i].enabled) {
                BiquadCoeffs c = BiquadDesign::compute(
                    params_[i].type, sampleRate_,
                    params_[i].frequency, params_[i].gainDb, params_[i].q);
                biquads_[i].setCoefficientsImmediate(c);
            }
        }
    }

    // Full parametric band set
    void setBand(int band, float freq, float gainDb, float q,
                 BiquadType type, bool enabled) {
        if (band < 0 || band >= numBands_) return;
        params_[band].frequency = freq;
        params_[band].gainDb = gainDb;
        params_[band].q = std::max(0.01f, q);
        params_[band].type = type;
        params_[band].enabled = enabled;
        updateBiquad(band);
    }

    // Graphic EQ shortcut — just set gain, keep fixed freq/Q
    void setBandGain(int band, float gainDb) {
        if (band < 0 || band >= numBands_) return;
        params_[band].gainDb = gainDb;
        updateBiquad(band);
    }

    // Batch set all gains (for preset loading)
    void setAllGains(const float* gains, int count) {
        count = std::min(count, numBands_);
        for (int i = 0; i < count; i++) {
            params_[i].gainDb = gains[i];
            updateBiquad(i);
        }
    }

    // Scan all bands for maximum boost (for auto-gain compensation)
    float getPeakGain() const {
        float peak = 0.0f;
        for (int i = 0; i < numBands_; i++) {
            if (params_[i].enabled && params_[i].gainDb > peak) {
                peak = params_[i].gainDb;
            }
        }
        return peak;
    }

    // Process audio — cascade all active biquads
    void process(float* left, float* right, int numFrames) {
        if (!enabled_.load(std::memory_order_relaxed)) return;
        for (int i = 0; i < numBands_; i++) {
            // Skip bands at ~0 dB (bypass optimization)
            if (!params_[i].enabled || std::fabs(params_[i].gainDb) < 0.05f) continue;
            biquads_[i].process(left, right, numFrames);
        }
    }

    void setEnabled(bool enabled) { enabled_.store(enabled); }
    bool isEnabled() const { return enabled_.load(); }
    int numBands() const { return numBands_; }

private:
    void updateBiquad(int band) {
        if (std::fabs(params_[band].gainDb) < 0.05f || !params_[band].enabled) {
            // Near-zero gain or disabled — set to bypass and clear state
            biquads_[band].setCoefficients(BiquadCoeffs::bypass());
        } else {
            BiquadCoeffs c = BiquadDesign::compute(
                params_[band].type, sampleRate_,
                params_[band].frequency, params_[band].gainDb, params_[band].q);
            biquads_[band].setCoefficients(c);
        }
    }

    int numBands_;
    float sampleRate_;
    std::atomic<bool> enabled_{true};
    EqBandParams params_[MAX_EQ_BANDS];
    Biquad biquads_[MAX_EQ_BANDS];
};
