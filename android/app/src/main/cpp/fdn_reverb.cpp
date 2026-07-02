#include "fdn_reverb.h"
#include <cmath>
#include <algorithm>

// Jezar's original comb tuning values at 44100 Hz.
// R channel offsets by +23 samples for stereo decorrelation.
const int FDNReverb::kCombTuningL[NUM_COMBS] = {
    1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617
};
const int FDNReverb::kCombTuningR[NUM_COMBS] = {
    1139, 1211, 1300, 1379, 1445, 1514, 1580, 1640
};

// Allpass tuning values at 44100 Hz.
const int FDNReverb::kAllpassTuningL[NUM_ALLPASSES] = { 556, 441, 341, 225 };
const int FDNReverb::kAllpassTuningR[NUM_ALLPASSES] = { 579, 464, 364, 248 };

FDNReverb::FDNReverb()
    : sampleRate_(44100)
    , roomSize_(0.5f), roomSizeTarget_(0.5f)
    , decay_(0.5f), decayTarget_(0.5f)
    , damping_(0.3f), dampingTarget_(0.3f)
    , preDelayMs_(10.0f), preDelayMsTarget_(10.0f)
    , diffusion_(0.5f), diffusionTarget_(0.5f)
    , wetDry_(0.3f), wetDryTarget_(0.3f)
    , feedback_(0.84f)
    , damp_(0.12f)
    , preDelaySamples_(0)
{
}

void FDNReverb::init(int sampleRate) {
    sampleRate_ = sampleRate;
    float scale = static_cast<float>(sampleRate) / kReferenceSampleRate;

    // Initialize comb filters with scaled tuning
    // Room size scales delay lengths: 0.5x to 2.0x
    float sizeScale = 0.5f + 1.5f * roomSize_;
    for (int i = 0; i < NUM_COMBS; i++) {
        int sizeL = std::max(1, static_cast<int>(kCombTuningL[i] * scale * sizeScale));
        int sizeR = std::max(1, static_cast<int>(kCombTuningR[i] * scale * sizeScale));
        // Allocate max size (2x base) to allow runtime room size changes
        int maxL = static_cast<int>(kCombTuningL[i] * scale * 2.0f) + 16;
        int maxR = static_cast<int>(kCombTuningR[i] * scale * 2.0f) + 16;
        combsL_[i].init(maxL);
        combsR_[i].init(maxR);
    }

    // Initialize allpass filters with scaled tuning
    for (int i = 0; i < NUM_ALLPASSES; i++) {
        int sizeL = std::max(1, static_cast<int>(kAllpassTuningL[i] * scale));
        int sizeR = std::max(1, static_cast<int>(kAllpassTuningR[i] * scale));
        allpassesL_[i].init(sizeL);
        allpassesR_[i].init(sizeR);
        allpassesL_[i].setFeedback(diffusion_);
        allpassesR_[i].setFeedback(diffusion_);
    }

    // Pre-delay (max 250ms)
    int maxPreDelay = static_cast<int>(sampleRate * 0.25f) + 16;
    preDelayL_.init(maxPreDelay);
    preDelayR_.init(maxPreDelay);

    updateParams();
    reset();
}

void FDNReverb::reset() {
    for (int i = 0; i < NUM_COMBS; i++) {
        combsL_[i].clear();
        combsR_[i].clear();
    }
    for (int i = 0; i < NUM_ALLPASSES; i++) {
        allpassesL_[i].clear();
        allpassesR_[i].clear();
    }
    preDelayL_.clear();
    preDelayR_.clear();
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

void FDNReverb::updateParams() {
    // Map decay (0-1) to feedback (0.7 - 0.98)
    // Using Freeverb's proven mapping: feedback = decay * scaleRoom + offsetRoom
    feedback_ = decay_ * kScaleRoom + kOffsetRoom;
    feedback_ = std::clamp(feedback_, 0.0f, 0.98f);

    // Map damping (0-1) to filter coefficient
    damp_ = damping_ * kScaleDamp;

    // Pre-delay in samples
    preDelaySamples_ = static_cast<int>(preDelayMs_ * 0.001f * sampleRate_);

    // Apply to comb filters
    for (int i = 0; i < NUM_COMBS; i++) {
        combsL_[i].setFeedback(feedback_);
        combsR_[i].setFeedback(feedback_);
        combsL_[i].setDamp(damp_);
        combsR_[i].setDamp(damp_);
    }

    // Map diffusion (0-1) to allpass feedback (0.3 - 0.7)
    float apFeedback = 0.3f + diffusion_ * 0.4f;
    for (int i = 0; i < NUM_ALLPASSES; i++) {
        allpassesL_[i].setFeedback(apFeedback);
        allpassesR_[i].setFeedback(apFeedback);
    }
}

void FDNReverb::process(float* left, float* right, int numFrames) {
    // Denormal (flush-to-zero) protection for these feedback paths is set once
    // by RoomDSPEngine::process() (the sole caller) via its RAII DenormalGuard,
    // covering the entire DSP chain — so no local FPCR toggling is needed here.

    // Per-sample parameter smoothing rate
    constexpr float smoothRate = 0.001f;

    for (int i = 0; i < numFrames; i++) {
        // Smooth parameters toward targets
        roomSize_ += smoothRate * (roomSizeTarget_ - roomSize_);
        decay_    += smoothRate * (decayTarget_ - decay_);
        damping_  += smoothRate * (dampingTarget_ - damping_);
        preDelayMs_ += smoothRate * (preDelayMsTarget_ - preDelayMs_);
        diffusion_ += smoothRate * (diffusionTarget_ - diffusion_);
        wetDry_   += smoothRate * (wetDryTarget_ - wetDry_);

        // Update derived values every 32 samples
        if ((i & 31) == 0) {
            updateParams();
        }

        float dryL = left[i];
        float dryR = right[i];

        // Pre-delay
        float pdL = preDelayL_.process(dryL, preDelaySamples_);
        float pdR = preDelayR_.process(dryR, preDelaySamples_);

        // Mix to mono and apply input gain (standard Freeverb)
        float input = (pdL + pdR) * kFixedGain;

        // 8 parallel comb filters per channel
        float outL = 0.0f, outR = 0.0f;
        for (int c = 0; c < NUM_COMBS; c++) {
            outL += combsL_[c].process(input);
            outR += combsR_[c].process(input);
        }

        // 4 series allpass filters per channel
        for (int a = 0; a < NUM_ALLPASSES; a++) {
            outL = allpassesL_[a].process(outL);
            outR = allpassesR_[a].process(outR);
        }

        // Wet/dry mix
        float wetL = outL;
        float wetR = outR;

        float outSampleL = dryL * (1.0f - wetDry_) + wetL * wetDry_;
        float outSampleR = dryR * (1.0f - wetDry_) + wetR * wetDry_;

        // Safety clamp
        left[i]  = std::clamp(outSampleL, -4.0f, 4.0f);
        right[i] = std::clamp(outSampleR, -4.0f, 4.0f);
    }
}
