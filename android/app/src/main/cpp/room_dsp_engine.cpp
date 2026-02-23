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
    tone_.reinit((float)sampleRate_);
    limiter_.init(sampleRate_);
    mbc_.reinit((float)sampleRate_);
    reverb_.reset();
    stereoExpander_.reset();
    crossfeed_.reset();
}

void RoomDSPEngine::setPreampGain(float dB) {
    // Now supports full [-15, +15] dB range (attenuation AND boost)
    preampGainDb_ = std::max(-15.0f, std::min(15.0f, dB));
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
    // No-op: auto-gain compensation removed.
    // Preamp controls input level directly. EQ boosts are unrestricted.
    // The output limiter (when enabled) or the final hard clamp catches overs.
}

void RoomDSPEngine::process(float* buffer, int numFrames) {
    if (channels_ != 2 || numFrames <= 0) return;

    bool doEq = eqEnabled_.load(std::memory_order_relaxed);
    bool doTone = tone_.isEnabled();
    bool doMbc = mbc_.isEnabled();
    bool doExpand = stereoExpandEnabled_.load(std::memory_order_relaxed);
    bool doCrossfeed = crossfeedEnabled_.load(std::memory_order_relaxed);
    bool doReverb = reverbEnabled_.load(std::memory_order_relaxed);
    bool doLimiter = limiter_.isEnabled();

    // Early out if nothing is enabled
    if (!doEq && !doTone && !doMbc && !doExpand && !doCrossfeed && !doReverb && !doLimiter) return;

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
    //   [Preamp] -> [Graphic EQ] -> [Parametric EQ]
    //   -> [Tone Controls] -> [MBC] -> [Stereo Expand]
    //   -> [Crossfeed] -> [Reverb] -> [Output Limiter]

    if (doEq) {
        // Preamp with per-sample smoothing (sample-rate adaptive).
        // No auto-gain reduction — let the EQ boost freely.
        // The output limiter (when enabled) or final clamp handles overs.
        float preampTarget = preampLinear_;
        if (std::fabs(preampTarget - 1.0f) > 1e-6f || std::fabs(preampLinearSmoothed_ - 1.0f) > 1e-6f) {
            for (int i = 0; i < numFrames; i++) {
                preampLinearSmoothed_ += smoothCoeff_ * (preampTarget - preampLinearSmoothed_);
                left[i] *= preampLinearSmoothed_;
                right[i] *= preampLinearSmoothed_;
            }
        }
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

    // Output limiter — catches all peaks from the entire chain.
    // This is the key to sounding powerful without distortion.
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
