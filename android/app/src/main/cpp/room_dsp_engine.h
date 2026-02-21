#pragma once
#include "fdn_reverb.h"
#include "stereo_expander.h"
#include "crossfeed.h"
#include <atomic>

// Main DSP engine orchestrator.
// Processing chain: Stereo Expander -> Crossfeed -> FDN Reverb -> Output
// All parameter updates are lock-free (atomic targets, per-sample smoothing).
class RoomDSPEngine {
public:
    RoomDSPEngine();

    void init(int sampleRate, int channels);
    void reset();

    // Process interleaved stereo PCM float buffer in-place.
    // buffer: interleaved [L0, R0, L1, R1, ...]
    // numFrames: number of stereo frames (buffer has numFrames*2 samples)
    void process(float* buffer, int numFrames);

    // Reverb controls
    void setReverbEnabled(bool enabled)     { reverbEnabled_.store(enabled); }
    void setRoomSize(float v)               { reverb_.setRoomSize(v); }
    void setDecay(float v)                  { reverb_.setDecay(v); }
    void setDamping(float v)                { reverb_.setDamping(v); }
    void setPreDelay(float ms)              { reverb_.setPreDelay(ms); }
    void setDiffusion(float v)              { reverb_.setDiffusion(v); }
    void setReverbWetDry(float v)           { reverb_.setWetDry(v); }

    // Stereo expander controls
    void setStereoExpandEnabled(bool enabled) { stereoExpandEnabled_.store(enabled); }
    void setStereoWidth(float width)        { stereoExpander_.setWidth(width); }

    // Crossfeed controls
    void setCrossfeedEnabled(bool enabled)  { crossfeedEnabled_.store(enabled); }
    void setCrossfeedParams(float cutoffHz, float feedLevelDb) {
        crossfeed_.configure(cutoffHz, feedLevelDb);
    }

    bool isReverbEnabled() const            { return reverbEnabled_.load(); }
    bool isStereoExpandEnabled() const      { return stereoExpandEnabled_.load(); }
    bool isCrossfeedEnabled() const         { return crossfeedEnabled_.load(); }

private:
    FDNReverb reverb_;
    StereoExpander stereoExpander_;
    Crossfeed crossfeed_;

    std::atomic<bool> reverbEnabled_{false};
    std::atomic<bool> stereoExpandEnabled_{false};
    std::atomic<bool> crossfeedEnabled_{false};

    int sampleRate_;
    int channels_;
};
