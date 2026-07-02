#include "room_dsp_engine.h"
#include <cstring>
#include <algorithm>
#include <cmath>
#include <cstdint>

namespace {
// RAII guard that enables ARM flush-to-zero (FTZ) for the lifetime of the
// scope and restores the previous FPCR/FPSCR on exit. FTZ collapses denormal
// floats to zero, preventing the ~100x FPU slowdown that IIR feedback tails
// (EQ biquads, tone shelves, MBC, crossfeed, limiter, reverb) trigger on quiet
// passages and fade-outs. Setting it once here covers the ENTIRE DSP chain.
// No-op on non-ARM targets (e.g. the x86_64 emulator).
struct DenormalGuard {
#if defined(__aarch64__)
    uint64_t oldFpcr_;
    DenormalGuard() {
        __asm__ __volatile__("mrs %0, fpcr" : "=r"(oldFpcr_));
        __asm__ __volatile__("msr fpcr, %0" : : "r"(oldFpcr_ | (1ULL << 24)));
    }
    ~DenormalGuard() {
        __asm__ __volatile__("msr fpcr, %0" : : "r"(oldFpcr_));
    }
#elif defined(__arm__)
    unsigned int oldFpscr_;
    DenormalGuard() {
        __asm__ __volatile__("vmrs %0, fpscr" : "=r"(oldFpscr_));
        __asm__ __volatile__("vmsr fpscr, %0" : : "r"(oldFpscr_ | (1 << 24)));
    }
    ~DenormalGuard() {
        __asm__ __volatile__("vmsr fpscr, %0" : : "r"(oldFpscr_));
    }
#else
    DenormalGuard() {}
    ~DenormalGuard() {}
#endif
    DenormalGuard(const DenormalGuard&) = delete;
    DenormalGuard& operator=(const DenormalGuard&) = delete;
};
} // namespace

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

bool RoomDSPEngine::anyUpstreamBoost() const {
    // True if any active stage before the limiter can increase the signal
    // level enough to clip. Conservative by design: it errs toward "true"
    // (keep the limiter) whenever a stage's contribution is not provably
    // level-reducing, so gating the limiter can never remove real protection.
    bool eqOn = eqEnabled_.load(std::memory_order_relaxed);
    bool spkOn = speakerEqEnabled_.load(std::memory_order_relaxed);

    // Preamp is only applied when EQ or speaker-correction is active
    // (see process()), so a leftover positive preamp with EQ off is harmless.
    if ((eqOn || spkOn) && preampGainDb_ > 0.0f) return true;

    // User EQ: only a positive band boost can lift peaks; pure cuts cannot.
    if (eqOn && (graphicEq_.getPeakGain() > 0.0f ||
                 parametricEq_.getPeakGain() > 0.0f)) return true;

    // Speaker-correction EQ boost.
    if (spkOn && speakerEq_.getPeakGain() > 0.0f) return true;

    // Tone shelves only ever boost (gains clamped >= 0).
    if (tone_.isEnabled() && tone_.getPeakGain() > 0.0f) return true;

    // MBC pre/post makeup gain can lift peaks; keep the limiter whenever the
    // MBC is engaged (its cost dwarfs the limiter's, so this is essentially
    // free and avoids reasoning about per-band makeup at runtime).
    if (mbc_.isEnabled()) return true;

    // Spatial stages add energy / re-sum channels and can raise peaks.
    if (reverbEnabled_.load(std::memory_order_relaxed)) return true;
    if (crossfeedEnabled_.load(std::memory_order_relaxed)) return true;
    if (stereoExpandEnabled_.load(std::memory_order_relaxed)) return true;

    // Stem mode replaces the buffer with a summed stem mix that can exceed
    // unity — keep the limiter so those peaks stay protected.
    if (stemModeActive_.load(std::memory_order_relaxed) && stemMixer_.isLoaded())
        return true;

    return false;
}

void RoomDSPEngine::process(float* buffer, int numFrames) {
    if (channels_ != 2 || numFrames <= 0) return;

    // Enable flush-to-zero for the whole chain (denormal protection). The
    // previous FPCR is restored automatically when this scope exits.
    DenormalGuard denormalGuard;

    // Stem mode: replace ExoPlayer's decoded audio with stem mixer output.
    // ExoPlayer still provides timeline/seek/play-pause, but we override its
    // audio content with our mixed stems. DSP chain continues as normal after.
    bool doStems = stemModeActive_.load(std::memory_order_relaxed)
                   && stemMixer_.isLoaded();
    if (doStems) {
        stemMixer_.mix(buffer, numFrames);
    }

    bool doEq = eqEnabled_.load(std::memory_order_relaxed);
    bool doSpeakerEq = speakerEqEnabled_.load(std::memory_order_relaxed);
    bool doTone = tone_.isEnabled();
    bool doMbc = mbc_.isEnabled();
    bool doExpand = stereoExpandEnabled_.load(std::memory_order_relaxed);
    bool doCrossfeed = crossfeedEnabled_.load(std::memory_order_relaxed);
    bool doReverb = reverbEnabled_.load(std::memory_order_relaxed);

    // The limiter is a safety net for peaks created BY this chain. Only run it
    // when some upstream stage can actually raise the level enough to clip;
    // otherwise the output cannot exceed the (already-bounded) source and the
    // final hard clamp is a sufficient backstop. This lets a fully-idle chain
    // truly bypass instead of paying the limiter's per-sample log10/pow.
    bool doLimiter = limiter_.isEnabled() && anyUpstreamBoost();

    // Early out if nothing is enabled (but always continue if stems are active
    // since the buffer was just replaced and may need DSP processing)
    if (!doStems && !doEq && !doSpeakerEq && !doTone && !doMbc && !doExpand && !doCrossfeed && !doReverb && !doLimiter) return;

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
