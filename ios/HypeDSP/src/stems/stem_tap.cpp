#include "stem_tap.h"

#include "stem_engine.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>

namespace hype {
namespace stems {

namespace {

constexpr int kChunk = 2048;

int64_t nowMs() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::steady_clock::now().time_since_epoch())
        .count();
}

}  // namespace

StemTap::StemTap() : StemTap(StemEngine::instance()) {}

StemTap::StemTap(StemEngine& engine)
    : engine_(engine),
      capture_(kCaptureFrames),
      mix_(size_t(kChunk) * 2),
      v_(size_t(kChunk) * 2),
      d_(size_t(kChunk) * 2) {
    // Until the first origin, the app's current item is the best guess.
    flushedSinceOrigin_ = true;
    engine_.attach(this);
}

StemTap::~StemTap() { engine_.detach(this); }

// ---- Events --------------------------------------------------------------------

void StemTap::setSampleRate(int rate) {
    if (rate == rate_) return;
    rate_ = rate;
    alphaStep_ = rate > 0 ? 1.0f / (0.05f * float(rate)) : 1.0f;  // 50 ms crossfade
    gainCoeff_ = rate > 0 ? 1.0f - std::exp(-1.0f / (0.015f * float(rate))) : 1.0f;
    pubRate_.store(rate, std::memory_order_relaxed);
    originKnown_ = false;
    needOrigin_ = true;
    alpha_ = 0.0f;
    lagKnown_ = false;
    pubLagKnown_.store(false, std::memory_order_relaxed);
}

void StemTap::setKeys(uint32_t current, uint32_t next) {
    keyCurrent_.store(current, std::memory_order_relaxed);
    keyNext_.store(next, std::memory_order_relaxed);
    pubNext_.store(next, std::memory_order_relaxed);
    keysEpoch_.fetch_add(1, std::memory_order_release);
    engine_.poke();
}

void StemTap::onFlush() {
    originKnown_ = false;
    needOrigin_ = true;
    // A stream change followed by a flush is the sink reconfiguring at a
    // gapless boundary, not a seek: keep treating it as "move to next".
    if (streamChanged_) flushAfterStreamChange_ = true;
    else flushedSinceOrigin_ = true;
    alpha_ = 0.0f;  // what follows a flush is discontinuous anyway
}

void StemTap::onStreamChange() {
    streamChanged_ = true;
    needOrigin_ = true;
}

void StemTap::onBufferTime(int64_t mediaTimeUs) {
    if (!needOrigin_ || rate_ <= 0) return;
    seenKeysEpoch_ = keysEpoch_.load(std::memory_order_acquire);
    const uint32_t cur = keyCurrent_.load(std::memory_order_relaxed);
    const uint32_t nxt = keyNext_.load(std::memory_order_relaxed);
    uint32_t track = track_;
    if (flushedSinceOrigin_) {
        // A seek or a newly loaded source. The app initiated it, so its idea of
        // the current item is already right.
        track = cur;
        originFromFlush_ = true;
    } else if (streamChanged_ || flushAfterStreamChange_) {
        // A gapless transition: the renderer moved on before the app heard
        // about it — unless the app has already moved too.
        track = (cur != 0 && cur != track_) ? cur : nxt;
        originFromFlush_ = false;
    }
    const int64_t t = mediaTimeUs < 0 ? 0 : mediaTimeUs;
    pos_ = (t * int64_t(rate_) + 500000) / 1000000;
    originKnown_ = true;
    needOrigin_ = false;
    flushedSinceOrigin_ = false;
    streamChanged_ = false;
    flushAfterStreamChange_ = false;
    if (track != track_) beginTrack(track);
    newEpoch();  // the decode is re-aligned after every discontinuity
    pubPos_.store(pos_, std::memory_order_relaxed);
}

void StemTap::bindTrack(uint32_t track) {
    keyCurrent_.store(track, std::memory_order_relaxed);
    keysEpoch_.fetch_add(1, std::memory_order_release);
    seenKeysEpoch_ = keysEpoch_.load(std::memory_order_acquire);
    flushedSinceOrigin_ = false;
    beginTrack(track);
    newEpoch();
}

void StemTap::setPosition(int64_t framePos, bool discontinuity) {
    if (discontinuity || !originKnown_ || std::llabs(framePos - pos_) > 64) {
        if (discontinuity) alpha_ = 0.0f;
        pos_ = framePos;
        originKnown_ = true;
        newEpoch();
    } else {
        pos_ = framePos;
    }
}

void StemTap::beginTrack(uint32_t track) {
    track_ = track;
    pubTrack_.store(track, std::memory_order_relaxed);
    pubTrackStartMs_.store(nowMs(), std::memory_order_relaxed);
    lagKnown_ = false;
    pubLagKnown_.store(false, std::memory_order_relaxed);
}

void StemTap::newEpoch() {
    ++epoch_;
    lagKnown_ = false;
    pubLagKnown_.store(false, std::memory_order_relaxed);
    capturedCount_ = 0;
    captureDelay_ = 0;
    pubEpoch_.store(epoch_, std::memory_order_relaxed);
    captureState_.store(track_ != 0 ? 1 : 0, std::memory_order_release);
}

void StemTap::pickUpKeys() {
    const uint32_t e = keysEpoch_.load(std::memory_order_acquire);
    if (e == seenKeysEpoch_) return;
    seenKeysEpoch_ = e;
    const uint32_t cur = keyCurrent_.load(std::memory_order_relaxed);
    if (!originKnown_ || cur == 0 || cur == track_) return;
    // The app moved to another item after an origin that its own seek/load
    // produced (or before any track was known): follow it.
    if (originFromFlush_ || track_ == 0) {
        beginTrack(cur);
        newEpoch();
    }
}

// ---- Audio -----------------------------------------------------------------------

void StemTap::process(float* buf, int frames) {
    if (frames <= 0 || rate_ <= 0) return;
    pubLastMs_.store(nowMs(), std::memory_order_relaxed);
    pickUpKeys();
    if (!originKnown_ || track_ == 0) {
        alpha_ = 0.0f;
        return;
    }

    // Results from the worker.
    if (!lagKnown_ && lagEpoch_.load(std::memory_order_acquire) == epoch_) {
        lag_ = lagResult_.load(std::memory_order_relaxed);
        lagKnown_ = true;
        pubLag_.store(lag_, std::memory_order_relaxed);
        pubLagKnown_.store(true, std::memory_order_relaxed);
        captureState_.store(0, std::memory_order_relaxed);
    }
    const uint32_t rs = rejectSeq_.load(std::memory_order_acquire);
    if (rs != seenRejectSeq_) {
        seenRejectSeq_ = rs;
        if (!lagKnown_ && rejectEpoch_.load(std::memory_order_relaxed) == epoch_) {
            const uint32_t cur = keyCurrent_.load(std::memory_order_relaxed);
            const uint32_t nxt = keyNext_.load(std::memory_order_relaxed);
            const uint32_t other = (cur != 0 && cur != track_) ? cur : ((nxt != 0 && nxt != track_) ? nxt : 0);
            if (rejectTryOther_.load(std::memory_order_relaxed) && other != 0) {
                beginTrack(other);
                newEpoch();
            } else {
                capturedCount_ = 0;
                captureDelay_ = rate_ / 2;  // try another stretch of audio
                captureState_.store(1, std::memory_order_release);
            }
        }
    }

    // Capture live audio (mono) for alignment, starting where there is signal.
    if (!lagKnown_ && captureState_.load(std::memory_order_relaxed) == 1) {
        int i = 0;
        if (captureDelay_ > 0) {
            const int skip = std::min(captureDelay_, frames);
            captureDelay_ -= skip;
            i = skip;
        }
        if (capturedCount_ == 0 && i < frames) {
            double e = 0.0;
            for (int k = i; k < frames; ++k) {
                const float m = 0.5f * (buf[size_t(k) * 2] + buf[size_t(k) * 2 + 1]);
                e += double(m) * m;
            }
            if (e / double(frames - i) < 1e-7) {
                i = frames;  // near silence carries no timing: wait
            } else {
                captureStart_ = pos_ + i;
            }
        }
        for (; i < frames && capturedCount_ < kCaptureFrames; ++i) {
            capture_[size_t(capturedCount_++)] = 0.5f * (buf[size_t(i) * 2] + buf[size_t(i) * 2 + 1]);
        }
        if (capturedCount_ >= kCaptureFrames) {
            pubCaptureStart_.store(captureStart_, std::memory_order_relaxed);
            captureEpoch_.store(epoch_, std::memory_order_relaxed);
            captureState_.store(2, std::memory_order_release);
            engine_.poke();
        }
    }

    // Mix.
    float tv, td, ti;
    engine_.levels(&tv, &td, &ti);
    const bool want = engine_.engaged() && lagKnown_;
    if (!want && alpha_ <= 0.0f) {
        gV_ = tv;
        gD_ = td;
        gI_ = ti;
        pos_ += frames;
        pubPos_.store(pos_, std::memory_order_relaxed);
        pubMixing_.store(false, std::memory_order_relaxed);
        return;
    }
    const int64_t rampFrames = int64_t(1.0f / alphaStep_) + 1;
    // Coming in needs a run long enough for the next split to land before it
    // ends (else the original would be back a moment later); staying in only
    // needs room for the fade out.
    const int64_t engageFrames = std::max(rampFrames, toRate(engine_.readyLead(), rate_));
    int done = 0;
    while (done < frames) {
        const int n = std::min(frames - done, kChunk);
        const int64_t at = pos_ + done + lag_;
        int64_t runEnd = at;
        const int got = lagKnown_ ? engine_.readStems(track_, rate_, at, n, mix_.data(), v_.data(),
                                                      d_.data(), &runEnd)
                                  : 0;
        float* x = buf + size_t(done) * 2;
        if (got <= 0) {
            // No separated audio here; fading out would need stems we lack.
            // Rare: fades start rampFrames before a run ends (below).
            alpha_ = 0.0f;
            done += n;
            continue;
        }
        for (int i = 0; i < got; ++i) {
            const bool on = want && (runEnd - (at + i)) > (alpha_ > 0.0f ? rampFrames : engageFrames);
            alpha_ = on ? std::min(1.0f, alpha_ + alphaStep_) : std::max(0.0f, alpha_ - alphaStep_);
            gV_ += gainCoeff_ * (tv - gV_);
            gD_ += gainCoeff_ * (td - gD_);
            gI_ += gainCoeff_ * (ti - gI_);
            if (alpha_ <= 0.0f) continue;
            for (int ch = 0; ch < 2; ++ch) {
                const size_t k = size_t(i) * 2 + size_t(ch);
                const float m = mix_[k], vv = v_[k], dd = d_[k];
                const float s = gV_ * vv + gD_ * dd + gI_ * (m - vv - dd);
                x[k] += alpha_ * (s - x[k]);
            }
        }
        done += got;
    }
    pos_ += frames;
    pubPos_.store(pos_, std::memory_order_relaxed);
    pubMixing_.store(alpha_ > 0.0f, std::memory_order_relaxed);
}

// ---- Worker side ---------------------------------------------------------------

StemTap::View StemTap::view() const {
    View v;
    v.tap = const_cast<StemTap*>(this);
    v.track = pubTrack_.load(std::memory_order_relaxed);
    v.next = pubNext_.load(std::memory_order_relaxed);
    v.rate = pubRate_.load(std::memory_order_relaxed);
    v.pos = pubPos_.load(std::memory_order_relaxed);
    v.lag = pubLag_.load(std::memory_order_relaxed);
    v.lagKnown = pubLagKnown_.load(std::memory_order_relaxed);
    v.lastProcessMs = pubLastMs_.load(std::memory_order_relaxed);
    v.trackStartMs = pubTrackStartMs_.load(std::memory_order_relaxed);
    v.captureReady = captureState_.load(std::memory_order_acquire) == 2;
    v.epoch = pubEpoch_.load(std::memory_order_relaxed);
    v.mixing = pubMixing_.load(std::memory_order_relaxed);
    return v;
}

int StemTap::copyCapture(float* out, int maxFrames, int64_t* startFrame, uint32_t* epoch) {
    int expected = 2;
    if (!captureState_.compare_exchange_strong(expected, 3, std::memory_order_acq_rel)) return 0;
    const int n = std::min(maxFrames, kCaptureFrames);
    std::copy(capture_.begin(), capture_.begin() + n, out);
    *startFrame = pubCaptureStart_.load(std::memory_order_relaxed);
    *epoch = captureEpoch_.load(std::memory_order_relaxed);
    return n;
}

void StemTap::deliverLag(uint32_t epoch, int64_t lag) {
    lagResult_.store(lag, std::memory_order_relaxed);
    lagEpoch_.store(epoch, std::memory_order_release);
}

void StemTap::rejectCapture(uint32_t epoch, bool tryOther) {
    rejectEpoch_.store(epoch, std::memory_order_relaxed);
    rejectTryOther_.store(tryOther, std::memory_order_relaxed);
    rejectSeq_.fetch_add(1, std::memory_order_release);
}

}  // namespace stems
}  // namespace hype
