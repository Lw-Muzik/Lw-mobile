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

    // EQ init
    graphicEq_.initGraphic((float)sampleRate, MAX_EQ_BANDS);
    parametricEq_.init((float)sampleRate, MAX_EQ_BANDS);

    // MBC init
    mbc_.init((float)sampleRate);

    // Spatial effects init
    reverb_.init(sampleRate);
    crossfeed_.init(sampleRate);
    crossfeed_.configure(Crossfeed::kChuMoyCutoff, Crossfeed::kChuMoyFeed);

    // Reset smoothed gains to targets
    preampLinearSmoothed_ = preampLinear_;
    autoGainLinearSmoothed_ = autoGainLinear_;
}

void RoomDSPEngine::reset() {
    graphicEq_.reinit((float)sampleRate_);
    parametricEq_.reinit((float)sampleRate_);
    mbc_.reinit((float)sampleRate_);
    reverb_.reset();
    stereoExpander_.reset();
    crossfeed_.reset();
}

void RoomDSPEngine::setPreampGain(float dB) {
    preampGainDb_ = std::max(0.0f, std::min(15.0f, dB));
    preampLinear_ = std::pow(10.0f, preampGainDb_ / 20.0f);
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
    float peakBoost = std::max(graphicEq_.getPeakGain(),
                               parametricEq_.getPeakGain());
    float effectiveDb = preampGainDb_ - peakBoost;
    effectiveDb = std::max(-15.0f, effectiveDb);
    autoGainLinear_ = std::pow(10.0f, effectiveDb / 20.0f);
}

void RoomDSPEngine::process(float* buffer, int numFrames) {
    if (channels_ != 2 || numFrames <= 0) return;

    bool doEq = eqEnabled_.load(std::memory_order_relaxed);
    bool doMbc = mbc_.isEnabled();
    bool doExpand = stereoExpandEnabled_.load(std::memory_order_relaxed);
    bool doCrossfeed = crossfeedEnabled_.load(std::memory_order_relaxed);
    bool doReverb = reverbEnabled_.load(std::memory_order_relaxed);

    // Early out if nothing is enabled
    if (!doEq && !doMbc && !doExpand && !doCrossfeed && !doReverb) return;

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

    // Signal chain: Preamp+AutoGain -> Graphic EQ -> Parametric EQ -> MBC
    //               -> Stereo Expand -> Crossfeed -> Reverb

    if (doEq) {
        // Preamp + auto-gain with per-sample smoothing
        for (int i = 0; i < numFrames; i++) {
            preampLinearSmoothed_ += SMOOTH_COEFF * (preampLinear_ - preampLinearSmoothed_);
            autoGainLinearSmoothed_ += SMOOTH_COEFF * (autoGainLinear_ - autoGainLinearSmoothed_);
            float gain = preampLinearSmoothed_ * autoGainLinearSmoothed_;
            left[i] *= gain;
            right[i] *= gain;
        }
        graphicEq_.process(left, right, numFrames);
        parametricEq_.process(left, right, numFrames);
    }

    // MBC (after EQ, before spatial effects)
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

    // Re-interleave with safety clamp
    for (int i = 0; i < numFrames; i++) {
        buffer[i * 2]     = std::clamp(left[i],  -4.0f, 4.0f);
        buffer[i * 2 + 1] = std::clamp(right[i], -4.0f, 4.0f);
    }

    delete[] heapBuf;
}
