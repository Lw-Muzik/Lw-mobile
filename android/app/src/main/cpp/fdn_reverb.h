#pragma once
#include "delay_line.h"
#include "one_pole_filter.h"

// 8-channel Feedback Delay Network reverb.
// Two-stage design: diffusion front-end + feedback tail.
// Based on Signalsmith Audio's FDN approach (Hadamard/Householder mixing).
class FDNReverb {
public:
    static constexpr int NUM_CHANNELS = 8;
    static constexpr int NUM_DIFFUSION_STEPS = 4;

    FDNReverb();

    void init(int sampleRate);
    void reset();

    // Parameters (all 0.0 - 1.0 unless noted)
    void setRoomSize(float size);       // Scales delay lengths
    void setDecay(float decay);         // Maps to RT60 (0.1s - 15s)
    void setDamping(float damping);     // Feedback lowpass (0=bright, 1=dark)
    void setPreDelay(float ms);         // Pre-delay in ms (0 - 200)
    void setDiffusion(float diffusion); // Echo density
    void setWetDry(float mix);          // 0=dry, 1=fully wet

    // Process stereo pair in-place
    void process(float* left, float* right, int numFrames);

private:
    void updateDelayTimes();
    void updateDecayGain();

    int sampleRate_;

    // Parameters (smoothed)
    float roomSize_, roomSizeTarget_;
    float decay_, decayTarget_;
    float damping_, dampingTarget_;
    float preDelayMs_, preDelayMsTarget_;
    float diffusion_, diffusionTarget_;
    float wetDry_, wetDryTarget_;

    // Pre-delay
    DelayLine preDelayL_, preDelayR_;
    int preDelaySamples_;

    // Diffusion stage: 4 steps x 8 channels
    DelayLine diffusionDelays_[NUM_DIFFUSION_STEPS][NUM_CHANNELS];
    int diffusionDelaySamples_[NUM_DIFFUSION_STEPS][NUM_CHANNELS];
    bool diffusionPolarity_[NUM_DIFFUSION_STEPS][NUM_CHANNELS];

    // Feedback stage: 8 channels
    DelayLine feedbackDelays_[NUM_CHANNELS];
    int feedbackDelaySamples_[NUM_CHANNELS];
    OnePoleFilter dampingFilters_[NUM_CHANNELS];
    float decayGain_;

    // Base delay times in ms (before room size scaling)
    static const float kDiffusionDelayMs[NUM_DIFFUSION_STEPS][NUM_CHANNELS];
    static const float kFeedbackDelayMs[NUM_CHANNELS];
    static const bool kDiffusionPolarity[NUM_DIFFUSION_STEPS][NUM_CHANNELS];
};
