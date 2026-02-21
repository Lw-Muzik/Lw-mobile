#include "fdn_reverb.h"
#include "hadamard.h"
#include <cmath>
#include <algorithm>

// Diffusion delay times (ms) for each step x channel.
// Chosen as mutually non-divisible values for maximum echo density.
// Each step roughly doubles the delay range.
const float FDNReverb::kDiffusionDelayMs[NUM_DIFFUSION_STEPS][NUM_CHANNELS] = {
    { 1.03f, 1.09f, 1.21f, 1.37f, 1.49f, 1.63f, 1.79f, 1.93f },
    { 2.11f, 2.27f, 2.53f, 2.71f, 3.01f, 3.19f, 3.41f, 3.67f },
    { 4.13f, 4.37f, 4.79f, 5.17f, 5.53f, 5.89f, 6.23f, 6.71f },
    { 8.09f, 8.53f, 9.11f, 9.71f,10.31f,10.97f,11.59f,12.23f },
};

// Feedback delay times (ms) — base values scaled by room size.
const float FDNReverb::kFeedbackDelayMs[NUM_CHANNELS] = {
    25.31f, 27.47f, 30.13f, 33.79f, 37.43f, 41.17f, 45.29f, 49.51f
};

// Fixed polarity flips per diffusion step for phase diversity.
const bool FDNReverb::kDiffusionPolarity[NUM_DIFFUSION_STEPS][NUM_CHANNELS] = {
    { true, false, true,  true,  false, true,  false, true  },
    { false, true, true,  false, true,  false, true,  false },
    { true,  true, false, true,  false, false, true,  true  },
    { false, false, true, false, true,  true,  false, false },
};

FDNReverb::FDNReverb()
    : sampleRate_(48000)
    , roomSize_(0.5f), roomSizeTarget_(0.5f)
    , decay_(0.5f), decayTarget_(0.5f)
    , damping_(0.3f), dampingTarget_(0.3f)
    , preDelayMs_(10.0f), preDelayMsTarget_(10.0f)
    , diffusion_(0.7f), diffusionTarget_(0.7f)
    , wetDry_(0.3f), wetDryTarget_(0.3f)
    , preDelaySamples_(0)
    , decayGain_(0.85f)
{
}

void FDNReverb::init(int sampleRate) {
    sampleRate_ = sampleRate;
    int maxDelay = static_cast<int>(sampleRate * 0.25f); // 250ms max

    preDelayL_.resize(maxDelay);
    preDelayR_.resize(maxDelay);

    for (int step = 0; step < NUM_DIFFUSION_STEPS; step++) {
        for (int ch = 0; ch < NUM_CHANNELS; ch++) {
            diffusionDelays_[step][ch].resize(static_cast<int>(sampleRate * 0.015f)); // 15ms max
            diffusionPolarity_[step][ch] = kDiffusionPolarity[step][ch];
        }
    }

    for (int ch = 0; ch < NUM_CHANNELS; ch++) {
        feedbackDelays_[ch].resize(maxDelay);
    }

    updateDelayTimes();
    updateDecayGain();
    reset();
}

void FDNReverb::reset() {
    preDelayL_.clear();
    preDelayR_.clear();
    for (int step = 0; step < NUM_DIFFUSION_STEPS; step++) {
        for (int ch = 0; ch < NUM_CHANNELS; ch++) {
            diffusionDelays_[step][ch].clear();
        }
    }
    for (int ch = 0; ch < NUM_CHANNELS; ch++) {
        feedbackDelays_[ch].clear();
        dampingFilters_[ch].clear();
    }
}

void FDNReverb::setRoomSize(float size) {
    roomSizeTarget_ = std::clamp(size, 0.0f, 1.0f);
}

void FDNReverb::setDecay(float decay) {
    decayTarget_ = std::clamp(decay, 0.0f, 1.0f);
}

void FDNReverb::setDamping(float damping) {
    dampingTarget_ = std::clamp(damping, 0.0f, 1.0f);
}

void FDNReverb::setPreDelay(float ms) {
    preDelayMsTarget_ = std::clamp(ms, 0.0f, 200.0f);
}

void FDNReverb::setDiffusion(float diffusion) {
    diffusionTarget_ = std::clamp(diffusion, 0.0f, 1.0f);
}

void FDNReverb::setWetDry(float mix) {
    wetDryTarget_ = std::clamp(mix, 0.0f, 1.0f);
}

void FDNReverb::updateDelayTimes() {
    float sizeScale = 0.3f + 0.7f * roomSize_;

    for (int step = 0; step < NUM_DIFFUSION_STEPS; step++) {
        for (int ch = 0; ch < NUM_CHANNELS; ch++) {
            diffusionDelaySamples_[step][ch] = std::max(1,
                static_cast<int>(kDiffusionDelayMs[step][ch] * 0.001f * sampleRate_ * sizeScale));
        }
    }

    for (int ch = 0; ch < NUM_CHANNELS; ch++) {
        feedbackDelaySamples_[ch] = std::max(1,
            static_cast<int>(kFeedbackDelayMs[ch] * 0.001f * sampleRate_ * sizeScale));
    }

    preDelaySamples_ = static_cast<int>(preDelayMs_ * 0.001f * sampleRate_);
}

void FDNReverb::updateDecayGain() {
    // Map decay (0-1) to RT60 (0.1s - 15s) with exponential curve
    float rt60 = 0.1f * powf(150.0f, decay_);

    // Compute per-loop decay gain from RT60
    // Average feedback delay in seconds
    float avgDelayMs = 0.0f;
    for (int ch = 0; ch < NUM_CHANNELS; ch++) {
        avgDelayMs += kFeedbackDelayMs[ch];
    }
    avgDelayMs /= NUM_CHANNELS;
    float sizeScale = 0.3f + 0.7f * roomSize_;
    float avgDelaySec = avgDelayMs * 0.001f * sizeScale;

    // How many loops to reach -60dB
    float loopsPerRt60 = rt60 / avgDelaySec;
    float dbPerLoop = -60.0f / loopsPerRt60;
    decayGain_ = powf(10.0f, dbPerLoop * 0.05f);
    decayGain_ = std::clamp(decayGain_, 0.0f, 0.9995f);
}

void FDNReverb::process(float* left, float* right, int numFrames) {
    // Parameter smoothing rate (per-sample exponential approach)
    constexpr float smoothRate = 0.0005f;

    for (int i = 0; i < numFrames; i++) {
        // Smooth parameters
        roomSize_ += smoothRate * (roomSizeTarget_ - roomSize_);
        decay_    += smoothRate * (decayTarget_ - decay_);
        damping_  += smoothRate * (dampingTarget_ - damping_);
        preDelayMs_ += smoothRate * (preDelayMsTarget_ - preDelayMs_);
        diffusion_ += smoothRate * (diffusionTarget_ - diffusion_);
        wetDry_   += smoothRate * (wetDryTarget_ - wetDry_);

        // Update derived values periodically (every 32 samples)
        if ((i & 31) == 0) {
            updateDelayTimes();
            updateDecayGain();
            for (int ch = 0; ch < NUM_CHANNELS; ch++) {
                dampingFilters_[ch].setCoefficient(damping_);
            }
        }

        // Store dry signal
        float dryL = left[i];
        float dryR = right[i];

        // Pre-delay
        preDelayL_.write(dryL);
        preDelayR_.write(dryR);
        float pdL = preDelayL_.read(std::max(1, preDelaySamples_));
        float pdR = preDelayR_.read(std::max(1, preDelaySamples_));

        // Distribute stereo input to 8 channels
        // Even channels get L, odd channels get R
        float channels[NUM_CHANNELS];
        float inputGain = 0.25f; // Prevent buildup
        for (int ch = 0; ch < NUM_CHANNELS; ch++) {
            channels[ch] = ((ch & 1) == 0 ? pdL : pdR) * inputGain;
        }

        // Read feedback delay outputs and add to input
        float feedback[NUM_CHANNELS];
        for (int ch = 0; ch < NUM_CHANNELS; ch++) {
            feedback[ch] = feedbackDelays_[ch].read(feedbackDelaySamples_[ch]);
        }

        // Mix feedback with Householder matrix (energy-preserving)
        householder<NUM_CHANNELS>(feedback);

        // Apply damping and decay
        for (int ch = 0; ch < NUM_CHANNELS; ch++) {
            feedback[ch] = dampingFilters_[ch].process(feedback[ch]) * decayGain_;
        }

        // Add input to feedback
        for (int ch = 0; ch < NUM_CHANNELS; ch++) {
            channels[ch] += feedback[ch];
        }

        // Diffusion stages (controlled by diffusion parameter)
        float diffMix = diffusion_;
        int activeSteps = static_cast<int>(diffusion_ * NUM_DIFFUSION_STEPS + 0.5f);
        activeSteps = std::clamp(activeSteps, 1, NUM_DIFFUSION_STEPS);

        for (int step = 0; step < activeSteps; step++) {
            float mixed[NUM_CHANNELS];
            for (int ch = 0; ch < NUM_CHANNELS; ch++) {
                // Read from diffusion delay
                float delayed = diffusionDelays_[step][ch].read(diffusionDelaySamples_[step][ch]);
                // Apply polarity flip
                mixed[ch] = diffusionPolarity_[step][ch] ? delayed : -delayed;
            }

            // Hadamard mixing (multiplies echo count by 8 per step)
            hadamard8(mixed);

            // Write input + mixed output to delay line
            for (int ch = 0; ch < NUM_CHANNELS; ch++) {
                float input = channels[ch];
                float output = mixed[ch];
                diffusionDelays_[step][ch].write(input + output * diffMix);
                channels[ch] = input * (1.0f - diffMix) + output * diffMix;
            }
        }

        // Write to feedback delay lines
        for (int ch = 0; ch < NUM_CHANNELS; ch++) {
            feedbackDelays_[ch].write(channels[ch]);
        }

        // Sum channels to stereo output
        // Even channels -> L, odd channels -> R, with decorrelation signs
        float wetL = 0.0f, wetR = 0.0f;
        for (int ch = 0; ch < NUM_CHANNELS; ch += 2) {
            float sign = ((ch / 2) & 1) ? -1.0f : 1.0f;
            wetL += channels[ch] * sign;
            wetR += channels[ch + 1] * sign;
        }
        wetL *= 0.5f;
        wetR *= 0.5f;

        // Wet/dry mix
        left[i]  = dryL * (1.0f - wetDry_) + wetL * wetDry_;
        right[i] = dryR * (1.0f - wetDry_) + wetR * wetDry_;
    }
}
