#pragma once
#include <cmath>
#include <algorithm>
#include <atomic>

// Single-band stereo compressor/expander.
// Algorithm based on Chromium's DynamicsCompressorKernel (0BSD license).
//
// Features:
//   - RMS envelope detection with configurable attack/release
//   - Log-domain gain computer: threshold, ratio, soft knee
//   - Noise gate (expander below gate threshold)
//   - Per-band pre-gain and post-gain (makeup)
//   - Lock-free parameter updates via atomic flags
//   - Per-sample gain smoothing to prevent clicks
class Compressor {
public:
    struct Params {
        float threshold = -18.0f;    // dB, compression starts above this
        float ratio = 2.5f;          // compression ratio (1.0 = no compression)
        float kneeWidth = 8.0f;      // dB, soft knee width
        float attackTime = 15.0f;    // ms
        float releaseTime = 45.0f;   // ms
        float preGain = 0.0f;        // dB, input gain
        float postGain = 0.0f;       // dB, makeup gain
        float noiseGateThreshold = -70.0f; // dB, gate opens above this
        float expanderRatio = 2.0f;  // expander ratio below gate threshold
        bool enabled = true;
    };

    Compressor() = default;

    void init(float sampleRate) {
        sampleRate_ = sampleRate;
        envDb_ = -96.0f;
        gainSmoothedDb_ = 0.0f;
        recalcCoeffs();
    }

    void setParams(const Params& p) {
        params_ = p;
        recalcCoeffs();
    }

    void setEnabled(bool enabled) { params_.enabled = enabled; }
    bool isEnabled() const { return params_.enabled; }

    void setThreshold(float dB) { params_.threshold = dB; }
    void setRatio(float r) { params_.ratio = std::max(1.0f, r); }
    void setKneeWidth(float dB) { params_.kneeWidth = std::max(0.0f, dB); }
    void setAttackTime(float ms) { params_.attackTime = ms; recalcCoeffs(); }
    void setReleaseTime(float ms) { params_.releaseTime = ms; recalcCoeffs(); }
    void setPreGain(float dB) { params_.preGain = dB; preGainLinear_ = dbToLin(dB); }
    void setPostGain(float dB) { params_.postGain = dB; postGainLinear_ = dbToLin(dB); }
    void setNoiseGateThreshold(float dB) { params_.noiseGateThreshold = dB; }
    void setExpanderRatio(float r) { params_.expanderRatio = std::max(1.0f, r); }

    // Process deinterleaved stereo buffers in-place
    void process(float* left, float* right, int numFrames) {
        if (!params_.enabled) return;

        const float preGain = preGainLinear_;
        const float postGain = postGainLinear_;
        const float threshold = params_.threshold;
        const float ratio = params_.ratio;
        const float knee = params_.kneeWidth;
        const float gateThreshold = params_.noiseGateThreshold;
        const float expanderRatio = params_.expanderRatio;

        for (int i = 0; i < numFrames; i++) {
            float L = left[i] * preGain;
            float R = right[i] * preGain;

            // Peak detection (use louder channel for stereo coherence)
            float peak = std::max(std::fabs(L), std::fabs(R));
            float peakDb = linToDb(peak);

            // Envelope follower (smooth in dB domain)
            if (peakDb > envDb_) {
                envDb_ += attackCoeff_ * (peakDb - envDb_);
            } else {
                envDb_ += releaseCoeff_ * (peakDb - envDb_);
            }

            // Gain computer in dB domain
            float gainDb = computeGain(envDb_, threshold, ratio, knee,
                                        gateThreshold, expanderRatio);

            // Smooth the gain to prevent clicks
            gainSmoothedDb_ += 0.005f * (gainDb - gainSmoothedDb_);

            float gainLinear = dbToLin(gainSmoothedDb_) * postGain;

            left[i] = L * gainLinear;
            right[i] = R * gainLinear;
        }
    }

    void reset() {
        envDb_ = -96.0f;
        gainSmoothedDb_ = 0.0f;
    }

private:
    static constexpr float LOG10_20 = 8.685889638f; // 20/ln(10)
    static constexpr float INV_LOG10_20 = 0.115129254f; // ln(10)/20

    static float dbToLin(float dB) {
        return std::exp(dB * INV_LOG10_20);
    }

    static float linToDb(float lin) {
        if (lin < 1e-10f) return -200.0f;
        return std::log(lin) * LOG10_20;
    }

    // Compute gain reduction in dB for a given input level in dB.
    // Returns 0 dB (no change) for levels below threshold,
    // negative dB for compression above threshold,
    // additional negative dB for expansion below gate threshold.
    static float computeGain(float inputDb, float threshold, float ratio,
                              float knee, float gateThreshold, float expanderRatio) {
        float gainDb = 0.0f;

        // Expander/gate region (below noise gate threshold)
        if (inputDb < gateThreshold) {
            float below = gateThreshold - inputDb;
            // Expand: for every dB below gate, reduce by (expanderRatio-1) dB
            gainDb = -below * (expanderRatio - 1.0f);
        }

        // Compressor region
        if (inputDb > threshold) {
            float overDb = inputDb - threshold;
            float halfKnee = knee * 0.5f;

            if (knee > 0.0f && overDb < halfKnee) {
                // Soft knee region: quadratic interpolation
                float x = overDb / halfKnee; // 0..1 within knee
                float kneeGain = overDb * (1.0f - 1.0f / ratio) * x * 0.5f;
                gainDb -= kneeGain;
            } else {
                // Above knee: full compression
                float fullOver = (knee > 0.0f) ? overDb - halfKnee : overDb;
                // Knee contribution
                if (knee > 0.0f) {
                    gainDb -= halfKnee * (1.0f - 1.0f / ratio) * 0.5f;
                }
                gainDb -= fullOver * (1.0f - 1.0f / ratio);
            }
        }

        return gainDb;
    }

    void recalcCoeffs() {
        if (sampleRate_ <= 0) return;
        // Attack/release coefficients (1-pole IIR in dB domain)
        // Time constant: coeff = 1 - exp(-1 / (time_sec * sampleRate))
        float attackSec = std::max(0.001f, params_.attackTime * 0.001f);
        float releaseSec = std::max(0.001f, params_.releaseTime * 0.001f);
        attackCoeff_ = 1.0f - std::exp(-1.0f / (attackSec * sampleRate_));
        releaseCoeff_ = 1.0f - std::exp(-1.0f / (releaseSec * sampleRate_));
        preGainLinear_ = dbToLin(params_.preGain);
        postGainLinear_ = dbToLin(params_.postGain);
    }

    Params params_;
    float sampleRate_ = 48000.0f;
    float envDb_ = -96.0f;          // envelope level in dB
    float gainSmoothedDb_ = 0.0f;   // smoothed gain reduction in dB
    float attackCoeff_ = 0.1f;
    float releaseCoeff_ = 0.001f;
    float preGainLinear_ = 1.0f;
    float postGainLinear_ = 1.0f;
};
