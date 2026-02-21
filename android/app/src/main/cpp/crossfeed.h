#pragma once
#include <cmath>
#include <algorithm>

// BS2B-style crossfeed filter for headphone spatialization.
// Simulates how we hear speakers in a room:
// - Each ear receives a delayed, low-passed version of the opposite channel
// - A highboost filter compensates for high-frequency loss on the direct signal
// This reduces the "in-head" localization common with headphones.
class Crossfeed {
public:
    Crossfeed()
        : sampleRate_(48000)
        , lp_a0_(0), lp_b1_(0)
        , hb_a0_(1), hb_a1_(0), hb_b1_(0)
        , lp_stateL_(0), lp_stateR_(0)
        , hb_inL_(0), hb_inR_(0)
        , hb_outL_(0), hb_outR_(0)
    {}

    void init(int sampleRate) {
        sampleRate_ = sampleRate;
        reset();
    }

    // Configure crossfeed filter.
    // cutoffHz: crossover frequency (typically 500-1000 Hz)
    // feedLevel_dB: cross-feed level in dB (positive value, typically 2-10 dB)
    void configure(float cutoffHz, float feedLevel_dB) {
        cutoffHz = std::clamp(cutoffHz, 100.0f, 2000.0f);
        feedLevel_dB = std::clamp(feedLevel_dB, 1.0f, 15.0f);

        float feed = powf(10.0f, feedLevel_dB / -20.0f);
        float omega = 2.0f * 3.14159265f * cutoffHz / static_cast<float>(sampleRate_);

        // Lowpass for cross-channel signal (simulates head shadow + ITD)
        float x = expf(-omega);
        lp_a0_ = feed * (1.0f - x);
        lp_b1_ = x;

        // Highboost compensation on direct signal
        float omegaH = 2.0f * 3.14159265f * (cutoffHz * 1.4f) / static_cast<float>(sampleRate_);
        float xh = expf(-omegaH);
        float Gh = 1.0f / feed;
        hb_a0_ = 1.0f - Gh * (1.0f - xh);
        hb_a1_ = -xh;
        hb_b1_ = xh;
    }

    void process(float* left, float* right, int numFrames) {
        for (int i = 0; i < numFrames; i++) {
            float inL = left[i];
            float inR = right[i];

            // Cross-feed: lowpass filter on opposite channel
            float crossL = lp_a0_ * inR + lp_b1_ * lp_stateL_;
            float crossR = lp_a0_ * inL + lp_b1_ * lp_stateR_;
            lp_stateL_ = crossL;
            lp_stateR_ = crossR;

            // Highboost compensation on direct signal
            float directL = hb_a0_ * inL + hb_a1_ * hb_inL_ + hb_b1_ * hb_outL_;
            float directR = hb_a0_ * inR + hb_a1_ * hb_inR_ + hb_b1_ * hb_outR_;
            hb_inL_ = inL;
            hb_inR_ = inR;
            hb_outL_ = directL;
            hb_outR_ = directR;

            // Sum direct + cross-feed
            left[i]  = directL + crossL;
            right[i] = directR + crossR;
        }
    }

    void reset() {
        lp_stateL_ = lp_stateR_ = 0.0f;
        hb_inL_ = hb_inR_ = 0.0f;
        hb_outL_ = hb_outR_ = 0.0f;
    }

    // Standard BS2B presets
    // Preset 1: Default (30-degree speaker placement)
    static constexpr float kDefaultCutoff = 700.0f;
    static constexpr float kDefaultFeed = 4.5f;
    // Preset 2: Chu Moy (most popular)
    static constexpr float kChuMoyCutoff = 700.0f;
    static constexpr float kChuMoyFeed = 6.0f;
    // Preset 3: Jan Meier (subtle)
    static constexpr float kMeierCutoff = 650.0f;
    static constexpr float kMeierFeed = 9.5f;

private:
    int sampleRate_;
    // Lowpass filter coefficients
    float lp_a0_, lp_b1_;
    // Highboost filter coefficients
    float hb_a0_, hb_a1_, hb_b1_;
    // Filter states
    float lp_stateL_, lp_stateR_;
    float hb_inL_, hb_inR_;
    float hb_outL_, hb_outR_;
};
