#pragma once
#include "parametric_eq.h"
#include "multiband_compressor.h"
#include "tone_controls.h"
#include "limiter.h"
#include "fdn_reverb.h"
#include "stereo_expander.h"
#include "crossfeed.h"
#include <atomic>

// Main DSP engine orchestrator — professional-grade signal chain.
//
// Processing chain:
//   [Preamp] -> [Graphic EQ 32-band] -> [Parametric EQ 32-band]
//   -> [Tone Controls (Bass/Treble)] -> [MBC 10-band]
//   -> [Stereo Expander] -> [Crossfeed] -> [FDN Reverb]
//   -> [Output Limiter] -> Output
//
// Key design decisions:
//   - No auto-gain reduction — EQ boosts are unrestricted for full impact.
//     The output limiter (opt-in) or final hard clamp prevents DAC overflow.
//   - Tone controls AFTER EQ, BEFORE MBC: EQ shapes frequency, tone adds
//     power, MBC controls dynamics of the combined result
//   - Output limiter LAST: catches all peaks from the entire chain
//   - Preamp range [-15, +15] dB: supports both boost AND attenuation
//   - Sample-rate-adaptive smoothing for consistent behavior at all rates
//
// All processing runs in ExoPlayer AudioProcessor pipeline.
// No Android AudioEffect APIs — fully custom C++ DSP.
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

    // Tone controls (independent bass/treble knobs)
    void setToneEnabled(bool enabled)       { tone_.setEnabled(enabled); }
    bool isToneEnabled() const              { return tone_.isEnabled(); }

    void setBassGain(float dB)              { tone_.setBassGain(dB); recomputeAutoGain(); }
    void setBassFreq(float hz)              { tone_.setBassFreq(hz); }
    void setBassQ(float q)                  { tone_.setBassQ(q); }
    void setTrebleGain(float dB)            { tone_.setTrebleGain(dB); recomputeAutoGain(); }
    void setTrebleFreq(float hz)            { tone_.setTrebleFreq(hz); }
    void setTrebleQ(float q)                { tone_.setTrebleQ(q); }

    // Output limiter controls
    void setLimiterEnabled(bool enabled)    { limiter_.setEnabled(enabled); }
    bool isLimiterEnabled() const           { return limiter_.isEnabled(); }

    void setLimiterCeiling(float v)         { limiter_.setCeiling(v); }
    void setLimiterRelease(float ms)        { limiter_.setRelease(ms); }
    void setLimiterKnee(float dB)           { limiter_.setKnee(dB); }

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

    // Tone controls (bass/treble shelf filters)
    ToneControls tone_;

    // Preamp — supports [-15, +15] dB, no auto-gain reduction
    float preampGainDb_ = 0.0f;
    float preampLinear_ = 1.0f;
    float preampLinearSmoothed_ = 1.0f;

    // Output limiter
    OutputLimiter limiter_;

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

    // Per-sample smoothing coefficient — computed from sample rate
    float smoothCoeff_ = 0.001f;
};
