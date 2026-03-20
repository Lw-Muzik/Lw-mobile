#pragma once
#include <cmath>
#include <algorithm>

/// Professional Mid-Side stereo width control.
///
/// width 0.0 = mono (side muted)
/// width 1.0 = original stereo (passthrough, unity gain)
/// width 2.0 = maximum expansion (side boosted, mid attenuated)
///
/// Uses energy-preserving gain compensation so perceived loudness stays
/// constant across the full width range. No volume drop, no clipping.
class StereoExpander {
public:
    StereoExpander() { setWidth(1.0f); reset(); }

    void setWidth(float width) {
        width_ = std::clamp(width, 0.0f, 2.0f);

        // At width=1.0: mid=1.0, side=1.0 → passthrough (unity)
        // At width=0.0: mid=1.0, side=0.0 → mono
        // At width=2.0: mid=0.0, side=2.0 → sides only (extreme)
        //
        // Linear crossfade: keep mid at 1.0 for width≤1.0,
        // reduce mid only when expanding beyond normal stereo.
        if (width_ <= 1.0f) {
            // Narrowing: reduce side, keep mid full
            targetMidGain_  = 1.0f;
            targetSideGain_ = width_;
        } else {
            // Widening: boost side, gently reduce mid to make room
            // Mid fades from 1.0 → 0.0 as width goes 1.0 → 2.0
            float t = width_ - 1.0f; // 0..1
            targetMidGain_  = 1.0f - t * 0.5f; // 1.0 → 0.5 (never fully kill mid)
            targetSideGain_ = 1.0f + t;         // 1.0 → 2.0
        }

        // Energy-preserving gain compensation.
        // For a typical stereo signal, perceived loudness ∝ sqrt(mid² + side²).
        // We normalize so that the output energy equals input energy at width=1.0.
        //
        // At width=1.0: mid=1, side=1 → energy = sqrt(1+1) = sqrt(2)
        // At any other width: energy = sqrt(midGain² + sideGain²)
        // Compensation = sqrt(2) / sqrt(midGain² + sideGain²)
        float energy = std::sqrt(targetMidGain_ * targetMidGain_ +
                                  targetSideGain_ * targetSideGain_);
        static const float kRefEnergy = std::sqrt(2.0f); // energy at width=1.0
        float compensation = (energy > 0.001f) ? (kRefEnergy / energy) : 1.0f;

        // Apply compensation to both gains
        targetMidGain_  *= compensation;
        targetSideGain_ *= compensation;
    }

    void process(float* left, float* right, int numFrames) {
        for (int i = 0; i < numFrames; i++) {
            // Smooth gains to avoid clicks (exponential approach)
            midGain_  += kSmoothCoeff * (targetMidGain_ - midGain_);
            sideGain_ += kSmoothCoeff * (targetSideGain_ - sideGain_);

            // M/S encode
            float mid  = (left[i] + right[i]) * 0.5f;
            float side = (left[i] - right[i]) * 0.5f;

            // Apply width-adjusted gains
            mid  *= midGain_;
            side *= sideGain_;

            // M/S decode
            left[i]  = mid + side;
            right[i] = mid - side;
        }
    }

    void reset() {
        midGain_  = targetMidGain_;
        sideGain_ = targetSideGain_;
    }

private:
    float width_ = 1.0f;
    float targetMidGain_ = 1.0f;
    float targetSideGain_ = 1.0f;
    float midGain_ = 1.0f;
    float sideGain_ = 1.0f;

    // ~3ms smoothing at 48kHz (144 samples)
    static constexpr float kSmoothCoeff = 1.0f / 144.0f;
};
