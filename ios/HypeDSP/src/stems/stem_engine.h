#pragma once
// Live stem separation engine: one per process.
//
// Owns the model, a worker thread and a small pool of tracks. Players report
// what they are playing through their StemTaps; the worker decodes those
// tracks itself, separates ~11.8 s splits AHEAD of each playhead (the playhead
// first, then up to two splits ahead, then the next track's opening), and
// publishes them for the taps to mix. Nothing here ever blocks an audio thread.
//
// Threading:
//   * control calls (load, levels, armed, registerTrack) — any non-audio thread
//   * StemTap::process — audio threads, lock-free
//   * the worker — its own thread; the status callback is invoked on it.

#include "decoded_track.h"
#include "pcm_source.h"
#include "resampler.h"
#include "separator.h"
#include "stem_config.h"
#include "stem_store.h"
#include "stem_tap.h"
#include "stft.h"

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace hype {
namespace stems {

// JSON string-content escaping (no surrounding quotes), shared by the bridges.
std::string jsonEscape(const std::string& s);

struct StemStatus {
    std::string state = "idle";  // idle | preparing | ready | unavailable | error
    std::string reason;          // stream | protected | unsupported | decode | model
    double progress = 0.0;       // 0..1, while preparing the split at the playhead
    double aheadSeconds = 0.0;   // separated audio available past the playhead
    std::string trackKey;
    std::string nextKey;         // the item the player has queued after it, if any
    std::string toJson() const;
    bool sameAs(const StemStatus& o) const;
};

class StemEngine {
public:
    static StemEngine& instance();

    // A private engine (own worker) for unit tests.
    static std::unique_ptr<StemEngine> createForTesting(std::unique_ptr<Separator> separator);
    ~StemEngine();

    // ---- Configuration --------------------------------------------------
    void setCacheDir(const std::string& dir);

    // ---- Model (blocking: call from a background thread) -----------------
    bool loadModel(const std::string& dir, std::string* error);
    void unloadModel();
    bool modelLoaded() const;

    struct Benchmark {
        bool ok = false;
        double rtf = 0.0;  // compute time / audio time for one full split
        int millis = 0;
        std::string error;
    };
    Benchmark benchmark();

    // ---- Control ----------------------------------------------------------
    // Armed: the UI wants stems prepared (Stems tab open or a stem engaged).
    void setArmed(bool armed);
    // Effective gains 0..1 (a pad switched off is 0).
    void setLevels(float vocals, float drums, float instruments);

    // ---- Tracks -----------------------------------------------------------
    // Interns `key` (the player's URI for the track) and returns its id.
    // `factory` builds a decoder for a local file; a non-empty
    // `unavailableReason` marks the track as one stems never apply to. An
    // http(s) key is a stream: unavailable ("stream") until provideSource.
    uint32_t registerTrack(const std::string& key, PcmSourceFactory factory,
                           std::string unavailableReason);
    // A local copy of the stream registered (or yet to be registered) as
    // `key` — the app downloads it while stems are in use. From now on the
    // engine decodes the copy and aligns it to what the player streams.
    void provideSource(const std::string& key, PcmSourceFactory factory);

    // ---- Status -----------------------------------------------------------
    void setStatusCallback(std::function<void(const StemStatus&)> cb);
    StemStatus status() const;

    // ---- Used by StemTap --------------------------------------------------
    void attach(StemTap* tap);
    void detach(StemTap* tap);
    bool engaged() const { return engaged_.load(std::memory_order_relaxed); }
    // Model samples from starting a split to hearing it (audio-thread safe).
    // Stems only come in on a run at least this long, so the next split can
    // be ready before it ends rather than the original coming back meanwhile.
    int64_t readyLead() const;
    void levels(float* v, float* d, float* i) const {
        *v = levelV_.load(std::memory_order_relaxed);
        *d = levelD_.load(std::memory_order_relaxed);
        *i = levelI_.load(std::memory_order_relaxed);
    }
    // Audio thread: copy stems of `track` at `rate` from frame `pos`. Returns
    // frames copied; *runEnd = end of the contiguous separated run.
    int readStems(uint32_t track, int rate, int64_t pos, int count,
                  float* mix, float* v, float* d, int64_t* runEnd) const;
    // Wake the worker. Audio-thread safe (an atomic flag, no lock).
    void poke() { poke_.store(true, std::memory_order_release); }

    // Test helper: block until the worker has nothing left to do.
    bool waitUntilIdleForTesting(int timeoutMs);
    // Test helper: separate one split from a prepared 44.1 kHz input span
    // ([c*kStepSamples - kPad, +kInputSpan), interleaved stereo) and return
    // the whole reconstructed span of vocals and drums, interleaved.
    bool separateForTesting(const float* in44, std::vector<float>* vocals,
                            std::vector<float>* drums, std::string* error);

private:
    StemEngine();

    struct TrackInfo {
        std::string key;
        PcmSourceFactory factory;
        std::string reason;
        bool provided = false;  // a stream with a local copy (provideSource)
    };

    // Pooled per-track state. Never freed while the engine lives, so an audio
    // thread can never touch freed memory; reuse waits for readers to drain.
    struct TrackSlot {
        std::atomic<uint32_t> id{0};
        std::atomic<int> rate{0};
        StemStore store;
        // Worker-only below.
        std::unique_ptr<DecodedTrack> decoded;
        int64_t lengthR = -1;      // track length at `rate` once the decode ends
        int64_t lastUsedMs = 0;
        int64_t retiredMs = 0;
        bool needsFree = false;
    };
    static constexpr int kMaxTracks = 4;

    struct Job {
        TrackSlot* slot = nullptr;
        uint32_t track = 0;
        int64_t start = -1;  // owned start, model samples (see chunkOwnedEnd)
        int prio = 99;
        double ahead = 1e9;
        bool valid() const { return slot != nullptr; }
    };

    void ensureWorker();
    void workerLoop();
    void step();
    std::vector<StemTap::View> snapshotTaps();
    TrackInfo trackInfo(uint32_t id);
    void setReason(uint32_t id, const std::string& reason);
    TrackSlot* slotFor(uint32_t track, int rate, bool create, const std::vector<StemTap::View>& views,
                       int64_t now);
    bool ensureDecoding(TrackSlot* slot);
    void alignTap(const StemTap::View& v);
    Job pickJob(const std::vector<StemTap::View>& views, int64_t now);
    void considerChunk(Job* best, TrackSlot* slot, uint32_t track, int64_t start, int prio, double ahead);
    bool runJob(const Job& job);
    bool stillWanted(const Job& job);
    bool computeSplit(const float* in44, const std::atomic<bool>* cancel, std::string* error,
                      const std::function<void(double)>& progress, const Job* job);
    void cleanup(const std::vector<StemTap::View>& views, int64_t now, bool wanted);
    void freeSlot(TrackSlot* slot);
    void publishStatus(const std::vector<StemTap::View>& views, int64_t now, bool wanted);
    void ensureBuffers();
    void releaseBuffers();
    int64_t chunkEndR(int64_t start, int rate, int64_t lengthR) const;

    // Control state.
    std::atomic<bool> armed_{false};
    std::atomic<bool> engaged_{false};
    std::atomic<float> levelV_{1.0f}, levelD_{1.0f}, levelI_{1.0f};
    std::atomic<int64_t> lastWantedMs_{0};

    // Registry.
    mutable std::mutex regMu_;
    std::unordered_map<std::string, uint32_t> keyToId_;
    std::unordered_map<uint32_t, TrackInfo> tracks_;
    uint32_t nextId_ = 1;
    std::string cacheDir_;

    // Taps.
    std::mutex tapsMu_;
    std::vector<StemTap*> taps_;
    // Consecutive alignment misses per tap and epoch (worker only): each miss
    // doubles the search window; the second suggests the wrong track.
    struct Misses { uint32_t epoch = 0; int count = 0; };
    std::unordered_map<const StemTap*, Misses> misses_;
    std::vector<const StemTap*> detached_;

    // Model.
    mutable std::mutex modelMu_;
    std::unique_ptr<Separator> separator_;
    std::atomic<bool> modelLoaded_{false};
    bool testing_ = false;

    // Worker.
    std::thread worker_;
    std::once_flag workerOnce_;
    std::mutex wakeMu_;
    std::condition_variable wakeCv_;
    std::atomic<bool> poke_{false};
    std::atomic<bool> quit_{false};
    std::atomic<bool> busy_{false};
    TrackSlot pool_[kMaxTracks];

    // Split buffers (worker; allocated while a model is loaded).
    std::unique_ptr<StereoStft> stft_;
    Resampler resampler_;
    std::vector<float> in44_, inL_, inR_, mag_, eV_, eD_, sum_, tmp_;
    std::vector<float> accVL_, accVR_, accDL_, accDR_;
    std::vector<float> spec_;  // 4 * kSpecBins scratch + frames
    std::vector<float> avgV_, avgD_;

    // Status.
    mutable std::mutex statusMu_;
    StemStatus status_;
    std::function<void(const StemStatus&)> statusCb_;
    int64_t lastEmitMs_ = 0;
    std::atomic<uint32_t> jobTrack_{0};
    std::atomic<double> jobProgress_{0.0};
    // How long a split takes here, decode included (moving average, ms; 0
    // until the benchmark or the first job): where to start one after a seek.
    std::atomic<int64_t> jobMs_{0};
};

}  // namespace stems
}  // namespace hype
