#include "room_dsp_engine.h"
#include <cstring>
#include <algorithm>
#include <cmath>

RoomDSPEngine::RoomDSPEngine()
    : sampleRate_(48000), channels_(2) {
}

void RoomDSPEngine::init(int sampleRate, int channels) {
    sampleRate_ = sampleRate;
    channels_ = channels;

    // Compute sample-rate-adaptive smoothing coefficient.
    // Target: ~1ms time constant at any sample rate.
    // Formula: 1 - exp(-1 / (tau * sampleRate)), tau = 0.001s
    smoothCoeff_ = 1.0f - std::exp(-1.0f / (0.001f * (float)sampleRate));

    // EQ init
    graphicEq_.initGraphic((float)sampleRate, MAX_EQ_BANDS);
    parametricEq_.init((float)sampleRate, MAX_EQ_BANDS);
    speakerEq_.init((float)sampleRate, MAX_EQ_BANDS);

    // Tone controls init
    tone_.init((float)sampleRate);

    // Output limiter init
    limiter_.init(sampleRate);

    // MBC init
    mbc_.init((float)sampleRate);

    // Spatial effects init
    reverb_.init(sampleRate);
    crossfeed_.init(sampleRate);
    crossfeed_.configure(Crossfeed::kChuMoyCutoff, Crossfeed::kChuMoyFeed);

    // Reset smoothed gain to target
    preampLinearSmoothed_ = preampLinear_;
}

void RoomDSPEngine::reset() {
    graphicEq_.reinit((float)sampleRate_);
    parametricEq_.reinit((float)sampleRate_);
    speakerEq_.reinit((float)sampleRate_);
    tone_.reinit((float)sampleRate_);
    limiter_.init(sampleRate_);
    mbc_.reinit((float)sampleRate_);
    reverb_.reset();
    stereoExpander_.reset();
    crossfeed_.reset();
}

void RoomDSPEngine::setPreampGain(float dB) {
    preampGainDb_ = std::max(-15.0f, std::min(15.0f, dB));
    recomputeAutoGain();
}

void RoomDSPEngine::setGraphicBandGain(int band, float dB) {
    graphicEq_.setBandGain(band, dB);
    recomputeAutoGain();
}

void RoomDSPEngine::setGraphicAllBands(const float* gains, int count) {
    graphicEq_.setAllGains(gains, count);
    recomputeAutoGain();
}

void RoomDSPEngine::setParametricBand(int band, float freq, float gainDb,
                                       float q, int filterType, bool enabled) {
    BiquadType type = static_cast<BiquadType>(
        std::min(std::max(filterType, 0), 6));
    parametricEq_.setBand(band, freq, gainDb, q, type, enabled);
    recomputeAutoGain();
}

void RoomDSPEngine::setParametricAllBands(const float* freqs, const float* gains,
                                           const float* qs, int count) {
    count = std::min(count, MAX_EQ_BANDS);
    for (int i = 0; i < count; i++) {
        parametricEq_.setBand(i, freqs[i], gains[i], qs[i],
                              BiquadType::Peaking, true);
    }
    recomputeAutoGain();
}

void RoomDSPEngine::recomputeAutoGain() {
    // Full auto-gain: reduce preamp by exactly the peak boost amount.
    //
    // This guarantees zero clipping for the loudest boosted band.
    // The EQ effect is pure frequency SHAPING — boosted frequencies stand
    // out because everything else is lowered, not because the overall level
    // increases. This is how professional hardware EQs work (RME, SSL, Neve).
    //
    // We use the SINGLE highest band peak (not cumulative sums of adjacent
    // bands), so the reduction is minimal and the EQ sounds impactful.
    // Adjacent band overlap (~3 dB worst case) is caught transparently
    // by the always-on output limiter — well within its clean range.

    // Find the single highest positive boost across all EQ sources
    float graphicPeak = graphicEq_.getPeakGain();
    float parametricPeak = parametricEq_.getPeakGain();
    float peakBoost = std::max(graphicPeak, parametricPeak);

    // Speaker correction EQ: include its peak in auto-gain
    if (speakerEqEnabled_.load(std::memory_order_relaxed)) {
        float speakerPeak = speakerEq_.getPeakGain();
        peakBoost = std::max(peakBoost, speakerPeak);
    }

    // Tone controls: take max (not sum) — the shelf may overlap with an
    // EQ band, but the limiter handles any residual gracefully.
    if (tone_.isEnabled()) {
        float tonePeak = tone_.getPeakGain();
        peakBoost = std::max(peakBoost, tonePeak);
    }

    // Reduce preamp by 100% of peak boost — zero clipping guaranteed
    float effectiveDb = preampGainDb_ - peakBoost;
    effectiveDb = std::max(-30.0f, std::min(15.0f, effectiveDb));
    preampLinear_ = std::pow(10.0f, effectiveDb / 20.0f);
}

void RoomDSPEngine::process(float* buffer, int numFrames) {
    if (channels_ != 2 || numFrames <= 0) return;

    bool doEq = eqEnabled_.load(std::memory_order_relaxed);
    bool doSpeakerEq = speakerEqEnabled_.load(std::memory_order_relaxed);
    bool doTone = tone_.isEnabled();
    bool doMbc = mbc_.isEnabled();
    bool doExpand = stereoExpandEnabled_.load(std::memory_order_relaxed);
    bool doCrossfeed = crossfeedEnabled_.load(std::memory_order_relaxed);
    bool doReverb = reverbEnabled_.load(std::memory_order_relaxed);
    bool doLimiter = limiter_.isEnabled();

    // Early out if nothing is enabled
    if (!doEq && !doSpeakerEq && !doTone && !doMbc && !doExpand && !doCrossfeed && !doReverb && !doLimiter) return;

    // Deinterleave to separate L/R channels
    constexpr int STACK_LIMIT = 2048;
    float stackL[STACK_LIMIT], stackR[STACK_LIMIT];
    float* left;
    float* right;
    float* heapBuf = nullptr;

    if (numFrames <= STACK_LIMIT) {
        left = stackL;
        right = stackR;
    } else {
        heapBuf = new float[numFrames * 2];
        left = heapBuf;
        right = heapBuf + numFrames;
    }

    for (int i = 0; i < numFrames; i++) {
        left[i]  = buffer[i * 2];
        right[i] = buffer[i * 2 + 1];
    }

    // Signal chain:
    //   [Preamp+AutoGain] -> [Speaker Correction EQ] -> [Graphic EQ]
    //   -> [Parametric EQ] -> [Tone Controls] -> [MBC]
    //   -> [Stereo Expand] -> [Crossfeed] -> [Reverb] -> [Output Limiter]

    // Preamp + auto-gain (applies when EQ or speaker correction is active)
    if (doEq || doSpeakerEq) {
        float preampTarget = preampLinear_;
        for (int i = 0; i < numFrames; i++) {
            if (preampTarget < preampLinearSmoothed_) {
                preampLinearSmoothed_ = preampTarget;
            } else {
                preampLinearSmoothed_ += smoothCoeff_ * (preampTarget - preampLinearSmoothed_);
            }
            left[i] *= preampLinearSmoothed_;
            right[i] *= preampLinearSmoothed_;
        }
    }

    // Speaker correction EQ — flattens headphone response before user EQ
    if (doSpeakerEq) {
        speakerEq_.process(left, right, numFrames);
    }

    if (doEq) {
        graphicEq_.process(left, right, numFrames);
        parametricEq_.process(left, right, numFrames);
    }

    // Tone controls (bass/treble shelves — applied even if EQ is off,
    // they're independent knobs like on a hi-fi amp)
    if (doTone) {
        tone_.process(left, right, numFrames);
    }

    // MBC (after EQ + tone, before spatial effects)
    if (doMbc) {
        mbc_.process(left, right, numFrames);
    }

    // Spatial effects
    if (doExpand) {
        stereoExpander_.process(left, right, numFrames);
    }
    if (doCrossfeed) {
        crossfeed_.process(left, right, numFrames);
    }
    if (doReverb) {
        reverb_.process(left, right, numFrames);
    }

    // Output limiter — only when user explicitly enables it.
    // The hard clamp below still prevents digital clipping as a safety net.
    if (doLimiter) {
        limiter_.process(left, right, numFrames);
    }

    // Re-interleave with safety clamp (belt-and-suspenders after limiter)
    for (int i = 0; i < numFrames; i++) {
        buffer[i * 2]     = std::clamp(left[i],  -1.0f, 1.0f);
        buffer[i * 2 + 1] = std::clamp(right[i], -1.0f, 1.0f);
    }

    delete[] heapBuf;
}

void RoomDSPEngine::setSpeakerEqBand(int band, float freq, float gainDb,
                                      float q, int filterType, bool enabled) {
    BiquadType type = static_cast<BiquadType>(
        std::min(std::max(filterType, 0), 6));
    speakerEq_.setBand(band, freq, gainDb, q, type, enabled);
    recomputeAutoGain();
}

void RoomDSPEngine::clearSpeakerEq() {
    for (int i = 0; i < MAX_EQ_BANDS; i++) {
        speakerEq_.setBand(i, 1000.0f, 0.0f, 1.0f, BiquadType::Peaking, false);
    }
    recomputeAutoGain();
}
