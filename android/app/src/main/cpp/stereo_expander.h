#pragma once
#include <cmath>
#include <algorithm>

// Mid-Side stereo expander.
// Decomposes L/R into Mid (sum) and Side (difference),
// scales Side relative to Mid, then recomposes.
class StereoExpander {
public:
    StereoExpander() : midGain_(1.0f), sideGain_(1.0f),
        midGainSmoothed_(1.0f), sideGainSmoothed_(1.0f),
        width_(1.0f), widthTarget_(1.0f) {}

    // width: 0.0 = mono, 1.0 = normal stereo, 2.0 = maximum expansion
    void setWidth(float width) {
        widthTarget_ = std::clamp(width, 0.0f, 2.0f);
        float w = widthTarget_;
        midGain_  = 2.0f * (1.0f - w * 0.5f); // 2.0 at 0, 1.0 at 1, 0.0 at 2
        sideGain_ = 2.0f * w * 0.5f;           // 0.0 at 0, 1.0 at 1, 2.0 at 2
        // Normalize to prevent clipping
        float norm = 1.0f / std::max(midGain_ + sideGain_, 1.0f);
        midGain_ *= norm;
        sideGain_ *= norm;
    }

    void process(float* left, float* right, int numFrames) {
        constexpr float smoothRate = 0.001f;

        for (int i = 0; i < numFrames; i++) {
            // Per-sample gain smoothing to avoid clicks
            midGainSmoothed_  += smoothRate * (midGain_ - midGainSmoothed_);
            sideGainSmoothed_ += smoothRate * (sideGain_ - sideGainSmoothed_);

            float mid  = (left[i] + right[i]) * 0.5f;
            float side = (left[i] - right[i]) * 0.5f;

            mid  *= midGainSmoothed_;
            side *= sideGainSmoothed_;

            left[i]  = mid + side;
            right[i] = mid - side;
        }
    }

    void reset() {
        midGainSmoothed_ = midGain_;
        sideGainSmoothed_ = sideGain_;
    }

private:
    float midGain_, sideGain_;
    float midGainSmoothed_, sideGainSmoothed_;
    float width_, widthTarget_;
};
