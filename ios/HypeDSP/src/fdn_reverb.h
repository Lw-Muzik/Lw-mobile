#pragma once
#include <vector>
#include <cmath>
#include <algorithm>
#include <cstring>

// Lowpass-feedback comb filter (Schroeder/Moorer style).
// The core building block of Freeverb reverb.
class LBCFComb {
public:
    LBCFComb() : bufsize_(0), bufidx_(0), filterstore_(0.0f),
                  feedback_(0.85f), damp1_(0.2f), damp2_(0.8f) {}

    void init(int size) {
        buffer_.assign(size, 0.0f);
        bufsize_ = size;
        bufidx_ = 0;
        filterstore_ = 0.0f;
    }

    void setDamp(float val) {
        damp1_ = val;
        damp2_ = 1.0f - val;
    }

    void setFeedback(float val) { feedback_ = val; }

    void clear() {
        std::fill(buffer_.begin(), buffer_.end(), 0.0f);
        filterstore_ = 0.0f;
    }

    inline float process(float input) {
        float output = buffer_[bufidx_];
        // One-pole lowpass on feedback path (damping)
        filterstore_ = output * damp2_ + filterstore_ * damp1_;
        buffer_[bufidx_] = input + filterstore_ * feedback_;
        if (++bufidx_ >= bufsize_) bufidx_ = 0;
        return output;
    }

private:
    std::vector<float> buffer_;
    int bufsize_, bufidx_;
    float filterstore_;
    float feedback_;
    float damp1_, damp2_;
};

// Schroeder allpass filter.
// Standard allpass: output = -input + bufout; write(input + bufout * feedback)
// This is inherently energy-preserving: |H(z)| = 1 for all frequencies.
class SchroederAllpass {
public:
    SchroederAllpass() : bufsize_(0), bufidx_(0), feedback_(0.5f) {}

    void init(int size) {
        buffer_.assign(size, 0.0f);
        bufsize_ = size;
        bufidx_ = 0;
    }

    void setFeedback(float val) { feedback_ = val; }

    void clear() {
        std::fill(buffer_.begin(), buffer_.end(), 0.0f);
    }

    inline float process(float input) {
        float bufout = buffer_[bufidx_];
        float output = -input + bufout;
        buffer_[bufidx_] = input + bufout * feedback_;
        if (++bufidx_ >= bufsize_) bufidx_ = 0;
        return output;
    }

private:
    std::vector<float> buffer_;
    int bufsize_, bufidx_;
    float feedback_;
};

// Simple delay line for pre-delay.
class SimpleDelay {
public:
    SimpleDelay() : bufsize_(0), bufidx_(0) {}

    void init(int maxSize) {
        buffer_.assign(maxSize, 0.0f);
        bufsize_ = maxSize;
        bufidx_ = 0;
    }

    void clear() {
        std::fill(buffer_.begin(), buffer_.end(), 0.0f);
        bufidx_ = 0;
    }

    inline float process(float input, int delaySamples) {
        if (delaySamples <= 0) return input;
        if (delaySamples >= bufsize_) delaySamples = bufsize_ - 1;
        buffer_[bufidx_] = input;
        int readIdx = bufidx_ - delaySamples;
        if (readIdx < 0) readIdx += bufsize_;
        if (++bufidx_ >= bufsize_) bufidx_ = 0;
        return buffer_[readIdx];
    }

private:
    std::vector<float> buffer_;
    int bufsize_, bufidx_;
};

/**
 * Freeverb-based stereo reverb engine.
 *
 * Architecture (per channel):
 *   Pre-delay → 8 parallel LBCF comb filters → sum → 4 series allpass filters → output
 *
 * Based on Jezar's public domain Freeverb with enhancements:
 *   - Scalable delay times for room size control
 *   - Separate decay and damping controls
 *   - Pre-delay support (0-200ms)
 *   - Adjustable allpass diffusion
 *
 * Reference: https://ccrma.stanford.edu/~jos/pasp/Freeverb.html
 */
class FDNReverb {
public:
    static constexpr int NUM_COMBS = 8;
    static constexpr int NUM_ALLPASSES = 4;

    FDNReverb();

    void init(int sampleRate);
    void reset();

    // Parameters (all 0.0 - 1.0 unless noted)
    void setRoomSize(float size);       // Scales delay lengths (0=tiny, 1=huge)
    void setDecay(float decay);         // Feedback gain (0=short, 1=long tail)
    void setDamping(float damping);     // HF damping (0=bright, 1=dark)
    void setPreDelay(float ms);         // Pre-delay in ms (0-200)
    void setDiffusion(float diffusion); // Allpass feedback (0=sparse, 1=dense)
    void setWetDry(float mix);          // 0=dry, 1=fully wet

    // Process stereo pair in-place
    void process(float* left, float* right, int numFrames);

private:
    void updateParams();

    int sampleRate_;

    // Smoothed parameters
    float roomSize_, roomSizeTarget_;
    float decay_, decayTarget_;
    float damping_, dampingTarget_;
    float preDelayMs_, preDelayMsTarget_;
    float diffusion_, diffusionTarget_;
    float wetDry_, wetDryTarget_;

    // Derived
    float feedback_;
    float damp_;
    int preDelaySamples_;

    // Pre-delay
    SimpleDelay preDelayL_, preDelayR_;

    // Comb filters (8 per channel, L/R)
    LBCFComb combsL_[NUM_COMBS];
    LBCFComb combsR_[NUM_COMBS];

    // Allpass filters (4 per channel, L/R)
    SchroederAllpass allpassesL_[NUM_ALLPASSES];
    SchroederAllpass allpassesR_[NUM_ALLPASSES];

    // Base comb tuning at 44100 Hz (Jezar's original values)
    static const int kCombTuningL[NUM_COMBS];
    static const int kCombTuningR[NUM_COMBS];
    static const int kAllpassTuningL[NUM_ALLPASSES];
    static const int kAllpassTuningR[NUM_ALLPASSES];

    // Freeverb constants
    static constexpr float kFixedGain = 0.015f;
    static constexpr float kScaleRoom = 0.28f;
    static constexpr float kOffsetRoom = 0.7f;
    static constexpr float kScaleDamp = 0.4f;
    static constexpr float kReferenceSampleRate = 44100.0f;
};
