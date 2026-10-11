#pragma once
// One player's view of the stem engine, living on that player's audio thread.
//
// Every audio path that can carry music owns one StemTap: on Android each
// ExoPlayer's audio processor (two during a crossfade), on iOS each
// AVPlayerItem's MTAudioProcessingTap. The tap
//   * knows which track and which sample of it the next buffer holds,
//   * captures a little live audio after every discontinuity so the worker
//     can align its own decode to the player's samples,
//   * and replaces the buffer with  gV*V + gD*D + gI*(M - V - D)  while any
//     stem level is below 100% and separated audio exists for that range,
//     crossfading 50 ms whenever stems arrive or run out.
// process() never locks, allocates or waits.

#include "stem_config.h"

#include <atomic>
#include <cstdint>
#include <vector>

namespace hype {
namespace stems {

class StemEngine;

class StemTap {
public:
    StemTap();                          // attaches to StemEngine::instance()
    explicit StemTap(StemEngine& engine);
    ~StemTap();
    StemTap(const StemTap&) = delete;
    StemTap& operator=(const StemTap&) = delete;

    // ---- Playback-thread events -------------------------------------------
    void setSampleRate(int rate);

    // Android: which track the player is on and which comes next (any thread).
    void setKeys(uint32_t current, uint32_t next);
    // Android: the processor was flushed (seek, new source): the position is
    // unknown until the next onBufferTime().
    void onFlush();
    // Android: the renderer moved to another stream (gapless transition or a
    // jump to another item).
    void onStreamChange();
    // Android: media time (µs) of the buffer about to be processed.
    void onBufferTime(int64_t mediaTimeUs);

    // iOS: the tap is bound to one item for life, and every callback reports
    // its asset time exactly.
    void bindTrack(uint32_t track);
    void setPosition(int64_t framePos, bool discontinuity);

    // ---- Audio ------------------------------------------------------------
    // Interleaved stereo float, in place.
    void process(float* buf, int frames);

    // True while any stem audio is in the output (keeps the limiter on).
    bool active() const { return alpha_ > 0.0f; }

    // ---- Worker side (StemEngine, under its registry lock) ----------------
    struct View {
        StemTap* tap = nullptr;
        uint32_t track = 0;
        uint32_t next = 0;
        int rate = 0;
        int64_t pos = 0;          // player-domain frame of the last buffer end
        int64_t lag = 0;          // decode frame = player frame + lag
        bool lagKnown = false;
        int64_t lastProcessMs = 0;
        int64_t trackStartMs = 0;  // when the tap switched to this track
        bool captureReady = false;
        uint32_t epoch = 0;
        bool mixing = false;       // stems were in the last buffer
    };
    View view() const;
    // Takes the finished capture (once): returns its length and sets its
    // player-domain start frame and the epoch it belongs to.
    int copyCapture(float* out, int maxFrames, int64_t* startFrame, uint32_t* epoch);
    void deliverLag(uint32_t epoch, int64_t lag);
    // The capture did not match the decode. `tryOther`: the tap may be on the
    // wrong track (event order differs between gapless moves and jumps), so
    // switch to the other candidate the player named.
    void rejectCapture(uint32_t epoch, bool tryOther);

    static constexpr int kCaptureFrames = 8192;
    static constexpr int kMaxLag = 8192;  // first search window (±186 ms at 44.1 kHz); widened on misses

private:
    void newEpoch();
    void beginTrack(uint32_t track);
    void pickUpKeys();

    StemEngine& engine_;

    // Audio-thread state.
    int rate_ = 0;
    int64_t pos_ = 0;
    bool originKnown_ = false;
    bool needOrigin_ = false;
    bool flushedSinceOrigin_ = false;
    bool streamChanged_ = false;
    bool flushAfterStreamChange_ = false;  // a sink reconfiguring at a gapless boundary
    bool originFromFlush_ = false;
    uint32_t track_ = 0;
    uint32_t seenKeysEpoch_ = 0;
    uint32_t epoch_ = 0;
    int64_t lag_ = 0;
    bool lagKnown_ = false;
    int capturedCount_ = 0;
    int captureDelay_ = 0;          // frames to wait before re-capturing
    int64_t captureStart_ = 0;
    uint32_t seenRejectSeq_ = 0;
    float alpha_ = 0.0f;
    float alphaStep_ = 0.0f;
    float gainCoeff_ = 0.0f;
    float gV_ = 1.0f, gD_ = 1.0f, gI_ = 1.0f;
    std::vector<float> capture_;
    std::vector<float> mix_, v_, d_;

    // Keys from the app thread.
    std::atomic<uint32_t> keyCurrent_{0};
    std::atomic<uint32_t> keyNext_{0};
    std::atomic<uint32_t> keysEpoch_{0};

    // Published for the worker.
    std::atomic<uint32_t> pubTrack_{0};
    std::atomic<uint32_t> pubNext_{0};
    std::atomic<int> pubRate_{0};
    std::atomic<int64_t> pubPos_{0};
    std::atomic<int64_t> pubLastMs_{0};
    std::atomic<bool> pubMixing_{false};
    std::atomic<int64_t> pubTrackStartMs_{0};
    std::atomic<int64_t> pubLag_{0};
    std::atomic<bool> pubLagKnown_{false};
    std::atomic<uint32_t> pubEpoch_{0};
    std::atomic<int> captureState_{0};  // 0 idle, 1 capturing, 2 ready, 3 taken by the worker
    std::atomic<int64_t> pubCaptureStart_{0};
    std::atomic<uint32_t> captureEpoch_{0};

    // Results from the worker.
    std::atomic<uint32_t> lagEpoch_{0xffffffffu};
    std::atomic<int64_t> lagResult_{0};
    std::atomic<uint32_t> rejectEpoch_{0xffffffffu};
    std::atomic<uint32_t> rejectSeq_{0};
    std::atomic<bool> rejectTryOther_{false};
};

}  // namespace stems
}  // namespace hype
