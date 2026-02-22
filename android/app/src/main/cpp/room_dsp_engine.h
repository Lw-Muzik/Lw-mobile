#pragma once
#include "parametric_eq.h"
#include "multiband_compressor.h"
#include "fdn_reverb.h"
#include "stereo_expander.h"
#include "crossfeed.h"
#include <atomic>

// Main DSP engine orchestrator.
// Processing chain (Poweramp-inspired):
//   [Preamp+AutoGain] -> [Graphic EQ] -> [Parametric EQ] -> [MBC]
//   -> [Stereo Expander] -> [Crossfeed] -> [FDN Reverb] -> Output
//
// All processing runs in the ExoPlayer AudioProcessor pipeline.
// No Android AudioEffect APIs used — fully custom C++ DSP.
// All parameter updates are lock-free (atomic targets, per-sample smoothing).
class RoomDSPEngine {
public:
    RoomDSPEngine();

    void init(int sampleRate, int channels);
    void reset();

    // Process interleaved stereo PCM float buffer in-place.
    void process(float* buffer, int numFrames);

    // EQ controls
    void setEqEnabled(bool enabled)         { eqEnabled_.store(enabled); }
    bool isEqEnabled() const                { return eqEnabled_.load(); }

    void setPreampGain(float dB);
    void setGraphicBandGain(int band, float dB);
    void setGraphicAllBands(const float* gains, int count);
    void setParametricBand(int band, float freq, float gainDb, float q,
                           int filterType, bool enabled);
    void setParametricAllBands(const float* freqs, const float* gains,
                               const float* qs, int count);
    void recomputeAutoGain();

    // MBC controls
    void setMbcEnabled(bool enabled)        { mbc_.setEnabled(enabled); }
    bool isMbcEnabled() const               { return mbc_.isEnabled(); }

    void setMbcPreGain(float dB)            { mbc_.setAllPreGains(dB); }
    void setMbcNoiseGateThreshold(float dB) { mbc_.setAllNoiseGateThresholds(dB); }
    void setMbcKneeWidth(float dB)          { mbc_.setAllKneeWidths(dB); }
    void setMbcExpanderRatio(float r)       { mbc_.setAllExpanderRatios(r); }
    void setMbcThreshold(float dB)          { mbc_.setAllThresholds(dB); }
    void setMbcRatio(float r)               { mbc_.setAllRatios(r); }
    void setMbcAttackTime(float ms)         { mbc_.setAllAttackTimes(ms); }
    void setMbcReleaseTime(float ms)        { mbc_.setAllReleaseTimes(ms); }
    void setMbcPostGain(float dB)           { mbc_.setAllPostGains(dB); }

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
    // EQ
    ParametricEQ graphicEq_;
    ParametricEQ parametricEq_;
    std::atomic<bool> eqEnabled_{false};

    // Preamp
    float preampGainDb_ = 0.0f;
    float preampLinear_ = 1.0f;
    float preampLinearSmoothed_ = 1.0f;

    // Auto-gain compensation
    float autoGainLinear_ = 1.0f;
    float autoGainLinearSmoothed_ = 1.0f;

    // Multi-band compressor
    MultibandCompressor mbc_;

    // Spatial effects
    FDNReverb reverb_;
    StereoExpander stereoExpander_;
    Crossfeed crossfeed_;

    std::atomic<bool> reverbEnabled_{false};
    std::atomic<bool> stereoExpandEnabled_{false};
    std::atomic<bool> crossfeedEnabled_{false};

    int sampleRate_;
    int channels_;

    static constexpr float SMOOTH_COEFF = 0.001f;
};
