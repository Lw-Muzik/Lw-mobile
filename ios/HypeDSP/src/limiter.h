#pragma once
#include <cmath>
#include <algorithm>

// Stereo output limiter — true-peak, zero-overshoot, soft-knee.
// Placed at the very end of the DSP chain to catch peaks from EQ/tone boosts.
//
// Design: feed-forward peak limiter with per-sample envelope detection.
// - Attack: instant (gain reduction applied immediately — zero overshoot)
// - Release: configurable, default 100ms (smooth recovery, no pumping)
// - Soft knee: configurable width in dB (smooth transition into limiting)
// - Ceiling: output never exceeds this level (default 0.98 = -0.18 dBFS)
//
// Key: gain smoothing is ASYMMETRIC — instant for attack (prevents any
// sample from exceeding the ceiling), smooth for release (no pumping).
// The hard safety clamp inside process() should never trigger.
class OutputLimiter {
public:
    OutputLimiter() { reset(); }

    void init(int sampleRate) {
        sampleRate_ = sampleRate;
        computeCoefficients();
        reset();
    }

    void reset() {
        envDb_ = -96.0f;
        gainSmoothed_ = 1.0f;
    }

    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }

    // Ceiling: max output amplitude (0.0 - 1.0), default 0.98
    void setCeiling(float ceiling) {
        ceiling_ = std::max(0.01f, std::min(1.0f, ceiling));
        ceilingDb_ = 20.0f * std::log10(ceiling_);
    }

    // Release time in ms (10 - 500), default 50
    void setRelease(float ms) {
        releaseMs_ = std::max(10.0f, std::min(500.0f, ms));
        computeCoefficients();
    }

    // Soft knee width in dB (0 - 12), default 6
    void setKnee(float dB) {
        kneeDb_ = std::max(0.0f, std::min(12.0f, dB));
    }

    // Process audio through the limiter. The caller controls when to invoke
    // this — the limiter itself has no internal enabled check, so it always
    // processes when called. The engine invokes it when EQ/tone is active
    // (transparent safety net) or when the user explicitly enables it.
    void process(float* left, float* right, int numFrames) {
        for (int i = 0; i < numFrames; i++) {
            // Peak detection (stereo-linked)
            float peak = std::max(std::fabs(left[i]), std::fabs(right[i]));

            // Convert to dB (floor at -96 dB)
            float peakDb = (peak > 1e-5f)
                ? 20.0f * std::log10(peak)
                : -96.0f;

            // Envelope follower — instant attack, smooth release
            if (peakDb > envDb_) {
                envDb_ = peakDb;  // instant: track peak exactly
            } else {
                envDb_ = releaseCoeff_ * envDb_ + (1.0f - releaseCoeff_) * peakDb;
            }

            // Gain computer with soft knee
            float gainDb = computeGain(envDb_);

            // Convert to linear gain
            float gainLin = std::pow(10.0f, gainDb * 0.05f);

            // Asymmetric gain smoothing:
            // - Attack (gain decreasing): instant — zero overshoot
            // - Release (gain increasing): smooth — no pumping
            if (gainLin < gainSmoothed_) {
                gainSmoothed_ = gainLin;  // instant attack
            } else {
                gainSmoothed_ += releaseSmooth_ * (gainLin - gainSmoothed_);
            }

            // Apply gain
            left[i]  *= gainSmoothed_;
            right[i] *= gainSmoothed_;

            // Hard safety ceiling (should never trigger with instant attack)
            left[i]  = std::max(-ceiling_, std::min(ceiling_, left[i]));
            right[i] = std::max(-ceiling_, std::min(ceiling_, right[i]));
        }
    }

private:
    void computeCoefficients() {
        if (sampleRate_ <= 0) return;
        // Envelope release: smooth recovery (~100ms default)
        releaseCoeff_ = std::exp(-1.0f / (releaseMs_ * 0.001f * (float)sampleRate_));
        // Gain release smoothing: slightly slower than envelope for clean recovery
        releaseSmooth_ = 1.0f - std::exp(-1.0f / (releaseMs_ * 0.002f * (float)sampleRate_));
    }

    // Soft-knee gain computation in dB domain
    float computeGain(float inputDb) const {
        float overshoot = inputDb - ceilingDb_;

        if (kneeDb_ > 0.0f && overshoot > -kneeDb_ / 2.0f && overshoot < kneeDb_ / 2.0f) {
            // Soft knee region: quadratic transition
            float x = overshoot + kneeDb_ / 2.0f;
            float reduction = (x * x) / (2.0f * kneeDb_);
            return -reduction;
        } else if (overshoot >= kneeDb_ / 2.0f) {
            // Above knee: full limiting (brick wall, ratio = infinity)
            return -overshoot;
        }
        // Below knee: no gain reduction
        return 0.0f;
    }

    int sampleRate_ = 48000;
    bool enabled_ = false;  // Off by default — user opts in via settings

    float ceiling_ = 0.98f;
    float ceilingDb_ = -0.18f;  // 20*log10(0.98)
    float releaseMs_ = 100.0f;
    float kneeDb_ = 6.0f;

    float releaseCoeff_ = 0.0f;   // envelope release
    float releaseSmooth_ = 0.01f; // gain release smoothing
    float envDb_ = -96.0f;
    float gainSmoothed_ = 1.0f;
};
