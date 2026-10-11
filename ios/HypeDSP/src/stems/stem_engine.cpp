#include "stem_engine.h"

#include "align.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#if defined(__APPLE__)
#include <pthread.h>
#include <sys/qos.h>
#elif defined(__linux__)
#include <sys/resource.h>
#include <sys/syscall.h>
#include <unistd.h>
#endif

namespace hype {
namespace stems {

namespace {

int64_t nowMs() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::steady_clock::now().time_since_epoch())
        .count();
}

int64_t floorDiv(int64_t a, int64_t b) { return a >= 0 ? a / b : -((-a + b - 1) / b); }
int64_t ceilDiv(int64_t a, int64_t b) { return -floorDiv(-a, b); }

int16_t toI16(float x) {
    const float s = x * 32768.0f;
    if (s >= 32767.0f) return 32767;
    if (s <= -32768.0f) return -32768;
    return int16_t(std::lrintf(s));
}

}  // namespace

std::string jsonEscape(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 8);
    for (unsigned char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof buf, "\\u%04x", c);
                    out += buf;
                } else {
                    out += char(c);
                }
        }
    }
    return out;
}

namespace {

std::string percentDecode(const std::string& s) {
    std::string out;
    out.reserve(s.size());
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '%' && i + 2 < s.size()) {
            const char hex[3] = {s[i + 1], s[i + 2], 0};
            char* end = nullptr;
            const long v = std::strtol(hex, &end, 16);
            if (end == hex + 2) {
                out += char(v);
                i += 2;
                continue;
            }
        }
        out += s[i];
    }
    return out;
}

std::string keyToPath(const std::string& key) {
    if (key.rfind("file://", 0) == 0) return percentDecode(key.substr(7));
    return key;
}

bool startsWith(const std::string& s, const char* prefix) { return s.rfind(prefix, 0) == 0; }

int defaultThreads() {
    const unsigned hc = std::thread::hardware_concurrency();
    if (hc >= 8) return 4;
    if (hc >= 4) return 2;
    return 1;
}

constexpr int64_t kPlayingWindowMs = 1500;   // a tap that processed audio this recently is playing
constexpr int64_t kQuiesceMs = 500;          // readers drain before a retired slot is reused
constexpr int64_t kIdleReleaseMs = 15000;    // free track memory after this long un-armed
constexpr int64_t kUnusedReleaseMs = 30000;  // free a track no player refers to
constexpr double kNextTrackLeadSeconds = 40.0;
constexpr float kMinAlignScore = 0.8f;
constexpr int kBins = 2 * kSplitFrames * kNetBins;

}  // namespace

// ---- StemStatus ------------------------------------------------------------

std::string StemStatus::toJson() const {
    char nums[96];
    std::snprintf(nums, sizeof nums, "\"progress\":%.3f,\"aheadSeconds\":%.2f", progress, aheadSeconds);
    return std::string("{\"state\":\"") + jsonEscape(state) + "\",\"reason\":\"" + jsonEscape(reason) +
           "\"," + nums + ",\"trackKey\":\"" + jsonEscape(trackKey) + "\"}";
}

bool StemStatus::sameAs(const StemStatus& o) const {
    return state == o.state && reason == o.reason && trackKey == o.trackKey &&
           std::fabs(progress - o.progress) < 0.05 &&
           std::floor(aheadSeconds / 2.0) == std::floor(o.aheadSeconds / 2.0);
}

// ---- Lifecycle ---------------------------------------------------------------

StemEngine& StemEngine::instance() {
    // Deliberately leaked: ONNX Runtime aborts if its globals are torn down by
    // static destructors at process exit, and the worker lives as long as the
    // process anyway.
    static StemEngine* engine = new StemEngine();
    return *engine;
}

StemEngine::StemEngine() = default;

std::unique_ptr<StemEngine> StemEngine::createForTesting(std::unique_ptr<Separator> separator) {
    std::unique_ptr<StemEngine> e(new StemEngine());
    e->testing_ = true;
    e->separator_ = std::move(separator);
    if (e->separator_ && e->separator_->isLoaded()) {
        e->ensureBuffers();
        e->modelLoaded_ = true;
    }
    e->ensureWorker();
    return e;
}

StemEngine::~StemEngine() {
    quit_.store(true);
    wakeCv_.notify_all();
    if (worker_.joinable()) worker_.join();
}

void StemEngine::ensureWorker() {
    std::call_once(workerOnce_, [this] { worker_ = std::thread(&StemEngine::workerLoop, this); });
}

// ---- Configuration -----------------------------------------------------------

void StemEngine::setCacheDir(const std::string& dir) {
    std::lock_guard<std::mutex> lock(regMu_);
    cacheDir_ = dir;
}

void StemEngine::setExcludedPrefixes(const std::vector<std::string>& prefixes) {
    std::lock_guard<std::mutex> lock(regMu_);
    excluded_ = prefixes;
    // Re-evaluate tracks registered before the list arrived.
    for (auto& entry : tracks_) {
        if (entry.second.reason.empty() && isExcludedLocked(entry.second.key)) {
            entry.second.reason = "youtube";
        }
    }
}

bool StemEngine::isExcludedLocked(const std::string& key) const {
    const std::string path = keyToPath(key);
    for (const std::string& p : excluded_) {
        if (!p.empty() && path.compare(0, p.size(), p) == 0) return true;
    }
    return false;
}

// ---- Model -------------------------------------------------------------------

void StemEngine::ensureBuffers() {
    if (!stft_) stft_ = std::make_unique<StereoStft>();
    auto sized = [](std::vector<float>& v, size_t n) {
        if (v.size() != n) v.assign(n, 0.0f);
    };
    sized(in44_, size_t(kInputSpan) * 2);
    sized(inL_, size_t(kInputSpan));
    sized(inR_, size_t(kInputSpan));
    sized(mag_, size_t(kBins));
    sized(eV_, size_t(kBins));
    sized(eD_, size_t(kBins));
    sized(sum_, size_t(kBins));
    sized(tmp_, size_t(kBins));
    sized(accVL_, size_t(kInputSpan));
    sized(accVR_, size_t(kInputSpan));
    sized(accDL_, size_t(kInputSpan));
    sized(accDR_, size_t(kInputSpan));
    sized(spec_, size_t(12) * kSpecBins + size_t(4) * kNfft);
    sized(avgV_, size_t(2) * kSplitFrames);
    sized(avgD_, size_t(2) * kSplitFrames);
}

void StemEngine::releaseBuffers() {
    for (std::vector<float>* v : {&in44_, &inL_, &inR_, &mag_, &eV_, &eD_, &sum_, &tmp_, &accVL_,
                                  &accVR_, &accDL_, &accDR_, &spec_, &avgV_, &avgD_}) {
        std::vector<float>().swap(*v);
    }
    stft_.reset();
}

bool StemEngine::loadModel(const std::string& dir, std::string* error) {
    {
        std::lock_guard<std::mutex> lock(modelMu_);
        if (!separator_) separator_ = createSpleeterOnnx(defaultThreads());
        if (!separator_->load(dir, error)) {
            modelLoaded_.store(false);
            return false;
        }
        ensureBuffers();
        modelLoaded_.store(true);
    }
    ensureWorker();
    poke();
    wakeCv_.notify_all();
    return true;
}

void StemEngine::unloadModel() {
    std::lock_guard<std::mutex> lock(modelMu_);
    if (separator_) separator_->unload();
    modelLoaded_.store(false);
    releaseBuffers();
}

bool StemEngine::modelLoaded() const { return modelLoaded_.load(); }

StemEngine::Benchmark StemEngine::benchmark() {
    Benchmark b;
    std::lock_guard<std::mutex> lock(modelMu_);
    if (!separator_ || !separator_->isLoaded()) {
        b.error = "model not loaded";
        return b;
    }
    ensureBuffers();
    // Deterministic noise with a slow envelope stands in for music: the cost
    // of the nets does not depend on the content.
    std::vector<float> in(size_t(kInputSpan) * 2);
    uint32_t seed = 0x2545F491u;
    for (size_t i = 0; i < in.size(); ++i) {
        seed = seed * 1664525u + 1013904223u;
        const float noise = float(seed >> 8) * (1.0f / 8388608.0f) - 1.0f;
        in[i] = 0.2f * noise * (0.6f + 0.4f * std::sin(float(i) * 1e-4f));
    }
    std::string err;
    std::fill(mag_.begin(), mag_.end(), 0.01f);
    if (!separator_->run(kNetVocals, mag_.data(), tmp_.data(), &err)) {  // warm-up
        b.error = err;
        return b;
    }
    const auto t0 = std::chrono::steady_clock::now();
    if (!computeSplit(in.data(), &quit_, &err, nullptr, nullptr)) {
        b.error = err.empty() ? "benchmark failed" : err;
        return b;
    }
    const double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    b.ok = true;
    b.millis = int(secs * 1000.0);
    b.rtf = secs / (double(kStepSamples) / double(kModelRate));
    return b;
}

// ---- Control -----------------------------------------------------------------

void StemEngine::setArmed(bool armed) {
    armed_.store(armed);
    if (armed) lastWantedMs_.store(nowMs());
    ensureWorker();
    poke();
    wakeCv_.notify_all();
}

void StemEngine::setLevels(float vocals, float drums, float instruments) {
    auto clamp01 = [](float x) { return x < 0.0f ? 0.0f : (x > 1.0f ? 1.0f : x); };
    vocals = clamp01(vocals);
    drums = clamp01(drums);
    instruments = clamp01(instruments);
    levelV_.store(vocals);
    levelD_.store(drums);
    levelI_.store(instruments);
    const bool engaged = vocals < 0.999f || drums < 0.999f || instruments < 0.999f;
    engaged_.store(engaged);
    if (engaged) lastWantedMs_.store(nowMs());
    ensureWorker();
    poke();
    wakeCv_.notify_all();
}

// ---- Tracks ------------------------------------------------------------------

uint32_t StemEngine::registerTrack(const std::string& key, PcmSourceFactory factory,
                                   std::string unavailableReason) {
    uint32_t id;
    {
        std::lock_guard<std::mutex> lock(regMu_);
        if (unavailableReason.empty() && (startsWith(key, "http://") || startsWith(key, "https://"))) {
            unavailableReason = "stream";
        }
        if (unavailableReason.empty() && isExcludedLocked(key)) unavailableReason = "youtube";
        auto it = keyToId_.find(key);
        if (it != keyToId_.end()) {
            id = it->second;
        } else {
            id = nextId_++;
            keyToId_[key] = id;
        }
        TrackInfo& info = tracks_[id];
        info.key = key;
        if (factory) info.factory = std::move(factory);
        // A transient failure (decode) is retried when the player registers
        // the track again; a policy reason sticks.
        if (!unavailableReason.empty() || info.reason == "decode") info.reason = unavailableReason;
    }
    poke();
    return id;
}

StemEngine::TrackInfo StemEngine::trackInfo(uint32_t id) {
    std::lock_guard<std::mutex> lock(regMu_);
    auto it = tracks_.find(id);
    if (it == tracks_.end()) return TrackInfo{};
    return it->second;
}

void StemEngine::setReason(uint32_t id, const std::string& reason) {
    std::lock_guard<std::mutex> lock(regMu_);
    auto it = tracks_.find(id);
    if (it != tracks_.end()) it->second.reason = reason;
}

// ---- Taps --------------------------------------------------------------------

void StemEngine::attach(StemTap* tap) {
    std::lock_guard<std::mutex> lock(tapsMu_);
    taps_.push_back(tap);
}

void StemEngine::detach(StemTap* tap) {
    std::lock_guard<std::mutex> lock(tapsMu_);
    taps_.erase(std::remove(taps_.begin(), taps_.end(), tap), taps_.end());
    detached_.push_back(tap);  // the worker drops its bookkeeping for it
}

std::vector<StemTap::View> StemEngine::snapshotTaps() {
    std::lock_guard<std::mutex> lock(tapsMu_);
    std::vector<StemTap::View> views;
    views.reserve(taps_.size());
    for (StemTap* t : taps_) views.push_back(t->view());
    return views;
}

int StemEngine::readStems(uint32_t track, int rate, int64_t pos, int count, float* mix, float* v,
                          float* d, int64_t* runEnd) const {
    if (track == 0) return 0;
    for (const TrackSlot& s : pool_) {
        if (s.id.load(std::memory_order_acquire) != track) continue;
        if (s.rate.load(std::memory_order_relaxed) != rate) continue;
        const int n = s.store.read(pos, count, mix, v, d);
        if (runEnd) *runEnd = n > 0 ? s.store.readyUntil(pos) : pos;
        // The slot may have been retired while we copied.
        if (s.id.load(std::memory_order_acquire) != track) return 0;
        return n;
    }
    return 0;
}

// ---- Worker ------------------------------------------------------------------

void StemEngine::workerLoop() {
    // Below the UI and far below audio, but not "background" (on Android that
    // also means a CPU-capped cgroup, too slow to stay ahead of the playhead).
#if defined(__APPLE__)
    pthread_set_qos_class_self_np(QOS_CLASS_UTILITY, 0);
#elif defined(__linux__)
    setpriority(PRIO_PROCESS, static_cast<id_t>(syscall(SYS_gettid)), 4);
#endif
    while (!quit_.load()) {
        {
            std::unique_lock<std::mutex> lk(wakeMu_);
            wakeCv_.wait_for(lk, std::chrono::milliseconds(40),
                             [this] { return quit_.load() || poke_.load(std::memory_order_acquire); });
        }
        if (quit_.load()) break;
        poke_.store(false, std::memory_order_relaxed);
        step();
    }
}

void StemEngine::step() {
    const int64_t now = nowMs();
    {
        std::lock_guard<std::mutex> lock(tapsMu_);
        for (const StemTap* t : detached_) misses_.erase(t);
        detached_.clear();
    }
    const std::vector<StemTap::View> views = snapshotTaps();
    const bool wanted = armed_.load() || engaged_.load();
    if (wanted) lastWantedMs_.store(now);
    bool didWork = false;

    if (wanted) {
        for (const StemTap::View& v : views) {
            if (v.captureReady && v.track != 0 && trackInfo(v.track).reason.empty()) {
                alignTap(v);
                didWork = true;
            }
        }
    }

    if (wanted && modelLoaded_.load()) {
        const Job job = pickJob(views, now);
        if (job.valid()) {
            busy_.store(true);
            runJob(job);
            busy_.store(false);
            didWork = true;
            poke();  // re-plan straight away: there may be more to do
        }
    }

    cleanup(views, now, wanted);
    publishStatus(views, now, wanted);
    if (!didWork) jobTrack_.store(0);
}

bool StemEngine::waitUntilIdleForTesting(int timeoutMs) {
    const int64_t until = nowMs() + timeoutMs;
    int quiet = 0;
    while (nowMs() < until) {
        poke();
        wakeCv_.notify_all();
        std::this_thread::sleep_for(std::chrono::milliseconds(60));
        if (!busy_.load() && jobTrack_.load() == 0) {
            if (++quiet >= 3) return true;
        } else {
            quiet = 0;
        }
    }
    return false;
}

bool StemEngine::separateForTesting(const float* in44, std::vector<float>* vocals,
                                    std::vector<float>* drums, std::string* error) {
    std::lock_guard<std::mutex> lock(modelMu_);
    if (!separator_ || !separator_->isLoaded()) {
        if (error) *error = "model not loaded";
        return false;
    }
    ensureBuffers();
    if (!computeSplit(in44, &quit_, error, nullptr, nullptr)) return false;
    vocals->resize(size_t(kInputSpan) * 2);
    drums->resize(size_t(kInputSpan) * 2);
    for (int64_t i = 0; i < kInputSpan; ++i) {
        (*vocals)[size_t(i) * 2] = accVL_[size_t(i)];
        (*vocals)[size_t(i) * 2 + 1] = accVR_[size_t(i)];
        (*drums)[size_t(i) * 2] = accDL_[size_t(i)];
        (*drums)[size_t(i) * 2 + 1] = accDR_[size_t(i)];
    }
    return true;
}

StemEngine::TrackSlot* StemEngine::slotFor(uint32_t track, int rate, bool create,
                                           const std::vector<StemTap::View>& views, int64_t now) {
    for (TrackSlot& s : pool_) {
        if (s.id.load(std::memory_order_relaxed) == track && s.rate.load(std::memory_order_relaxed) == rate) {
            s.lastUsedMs = now;
            return &s;
        }
    }
    if (!create) return nullptr;

    TrackSlot* pick = nullptr;
    for (TrackSlot& s : pool_) {
        if (s.id.load(std::memory_order_relaxed) == 0 && now - s.retiredMs >= kQuiesceMs) {
            pick = &s;
            break;
        }
    }
    if (!pick) {
        // Retire the least recently used track no player needs; it becomes
        // reusable once readers have drained.
        TrackSlot* victim = nullptr;
        for (TrackSlot& s : pool_) {
            const uint32_t id = s.id.load(std::memory_order_relaxed);
            if (id == 0) continue;
            bool needed = false;
            for (const StemTap::View& v : views) needed = needed || v.track == id || v.next == id;
            if (needed) continue;
            if (!victim || s.lastUsedMs < victim->lastUsedMs) victim = &s;
        }
        if (victim) {
            victim->id.store(0, std::memory_order_release);
            victim->retiredMs = now;
            victim->needsFree = true;
        }
        return nullptr;
    }
    if (pick->needsFree) freeSlot(pick);
    pick->store.configure(toRate(kStepSamples + kMargin, rate) + 4);
    pick->decoded.reset();
    pick->lengthR = -1;
    pick->lastUsedMs = now;
    pick->rate.store(rate, std::memory_order_relaxed);
    pick->id.store(track, std::memory_order_release);
    return pick;
}

void StemEngine::freeSlot(TrackSlot* slot) {
    slot->decoded.reset();  // deletes the cache file
    slot->store.configure(0);
    slot->lengthR = -1;
    slot->needsFree = false;
}

bool StemEngine::ensureDecoding(TrackSlot* slot) {
    const uint32_t id = slot->id.load(std::memory_order_relaxed);
    const TrackInfo info = trackInfo(id);
    if (slot->decoded) {
        if (!slot->decoded->failed()) return true;
        if (!info.reason.empty()) return false;
        // The player registered the track again after a decode error: retry.
        slot->decoded.reset();
        slot->store.invalidate();
        slot->lengthR = -1;
    }
    if (!info.reason.empty()) return false;
    if (!info.factory) {
        setReason(id, "unsupported");
        return false;
    }
    std::unique_ptr<PcmSource> src = info.factory();
    if (!src) {
        setReason(id, "unsupported");
        return false;
    }
    std::string dir;
    {
        std::lock_guard<std::mutex> lock(regMu_);
        dir = cacheDir_;
    }
    if (dir.empty()) {
        const char* tmp = std::getenv("TMPDIR");
        dir = tmp ? tmp : "/tmp";
    }
    auto decoded = std::make_unique<DecodedTrack>(dir + "/hype_stems_" + std::to_string(id) + "_" +
                                                  std::to_string(slot->rate.load()) + ".pcm");
    std::string reason;
    if (!decoded->begin(std::move(src), &reason)) {
        setReason(id, reason.empty() ? "decode" : reason);
        return false;
    }
    slot->decoded = std::move(decoded);
    return true;
}

void StemEngine::alignTap(const StemTap::View& v) {
    const int64_t now = nowMs();
    const std::vector<StemTap::View> views = snapshotTaps();
    TrackSlot* slot = slotFor(v.track, v.rate, true, views, now);
    if (!slot || !ensureDecoding(slot)) return;

    std::vector<float> cap(StemTap::kCaptureFrames);
    int64_t p0 = 0;
    uint32_t epoch = 0;
    int n = 0;
    {
        std::lock_guard<std::mutex> lock(tapsMu_);
        if (std::find(taps_.begin(), taps_.end(), v.tap) == taps_.end()) return;
        n = v.tap->copyCapture(cap.data(), int(cap.size()), &p0, &epoch);
    }
    if (n <= 0) return;

    const int R = v.rate;
    DecodedTrack* dec = slot->decoded.get();
    const int F = dec->sampleRate();
    Misses& miss = misses_[v.tap];
    if (miss.epoch != epoch) miss = Misses{epoch, 0};
    const int L = StemTap::kMaxLag << std::min(miss.count, 4);  // up to ±3 s at 44.1 kHz
    const int64_t refStart = p0 - L;
    const int refLen = n + 2 * L;
    std::vector<float> st(size_t(refLen) * 2);
    if (F == R) {
        dec->decodeUntil(refStart + refLen + 1, &quit_);
        dec->read(refStart, refLen, st.data());
    } else {
        const int H = resampler_.halfWidth(F, R);
        const int64_t fA = floorDiv(refStart * F, R) - H;
        const int64_t fB = ceilDiv((refStart + refLen) * F, R) + H;
        dec->decodeUntil(fB + 1, &quit_);
        std::vector<float> tmp(size_t(fB - fA) * 2);
        dec->read(fA, fB - fA, tmp.data());
        resampler_.process(tmp.data(), fA, fB - fA, F, st.data(), refStart, refLen, R);
    }
    std::vector<float> ref(refLen);
    for (int i = 0; i < refLen; ++i) ref[i] = 0.5f * (st[size_t(i) * 2] + st[size_t(i) * 2 + 1]);

    int lag = 0;
    float score = 0.0f;
    const bool ok = findLag(cap.data(), n, ref.data(), L, &lag, &score);
    std::lock_guard<std::mutex> lock(tapsMu_);
    if (std::find(taps_.begin(), taps_.end(), v.tap) == taps_.end()) return;
    if (ok && score >= kMinAlignScore) {
        v.tap->deliverLag(epoch, lag);
        misses_.erase(v.tap);
    } else {
        ++miss.count;
        v.tap->rejectCapture(epoch, /*tryOther=*/miss.count == 2);
    }
}

int64_t StemEngine::ownedStartR(int64_t split, int rate) const {
    return toRate(splitOwnedStart(split), rate);
}

int64_t StemEngine::ownedEndR(int64_t split, int rate, int64_t lengthR) const {
    const int64_t e = toRate(splitOwnedEnd(split), rate);
    return lengthR >= 0 ? std::min(e, lengthR) : e;
}

void StemEngine::considerSplit(Job* best, TrackSlot* slot, uint32_t track, int64_t split, int prio,
                               double ahead) {
    if (!best->valid() || prio < best->prio || (prio == best->prio && ahead < best->ahead)) {
        best->slot = slot;
        best->track = track;
        best->split = split;
        best->prio = prio;
        best->ahead = ahead;
    }
}

StemEngine::Job StemEngine::pickJob(const std::vector<StemTap::View>& views, int64_t now) {
    Job best;
    auto upcoming = [&](uint32_t track, int rate) {
        if (track == 0 || !trackInfo(track).reason.empty()) return;
        TrackSlot* slot = slotFor(track, rate, true, views, now);
        if (!slot || !ensureDecoding(slot)) return;
        const int64_t a = ownedStartR(0, rate);
        const int64_t b = ownedEndR(0, rate, slot->lengthR);
        if (a < b && !slot->store.covers(a, b)) considerSplit(&best, slot, track, 0, 2, 0.0);
    };

    for (const StemTap::View& v : views) {
        if (v.track == 0 || v.rate <= 0) continue;
        const bool playing = v.lastProcessMs > 0 && now - v.lastProcessMs < kPlayingWindowMs;
        if (!playing) {
            // iOS queues the next item with its own tap before it plays.
            if (v.lastProcessMs == 0) upcoming(v.track, v.rate);
            continue;
        }
        if (!trackInfo(v.track).reason.empty()) continue;
        TrackSlot* slot = slotFor(v.track, v.rate, true, views, now);
        if (!slot || !ensureDecoding(slot)) continue;

        const int64_t dpos = std::max<int64_t>(0, v.pos + (v.lagKnown ? v.lag : 0));
        const int64_t c = splitContaining(dpos * kModelRate / v.rate);
        for (int k = 0; k < 3; ++k) {
            const int64_t a = ownedStartR(c + k, v.rate);
            const int64_t b = ownedEndR(c + k, v.rate, slot->lengthR);
            if (a >= b) break;
            if (!slot->store.covers(k == 0 ? std::max(a, dpos) : a, b)) {
                const double ahead = double(slot->store.readyUntil(dpos) - dpos) / double(v.rate);
                considerSplit(&best, slot, v.track, c + k, k == 0 ? 0 : 1, ahead);
                break;
            }
        }

        if (v.next != 0 && v.next != v.track) {
            int64_t length = slot->lengthR;
            if (length < 0 && slot->decoded && slot->decoded->durationEstimate() > 0) {
                length = slot->decoded->durationEstimate() * v.rate / slot->decoded->sampleRate();
            }
            if (length > 0 && double(length - dpos) / double(v.rate) < kNextTrackLeadSeconds) {
                upcoming(v.next, v.rate);
            }
        }
    }
    return best;
}

bool StemEngine::stillWanted(const Job& job) {
    if (quit_.load()) return false;
    if (!(armed_.load() || engaged_.load())) return false;
    if (job.prio == 2) return true;
    const std::vector<StemTap::View> views = snapshotTaps();
    for (const StemTap::View& v : views) {
        if (v.next == job.track) return true;
        if (v.track != job.track || v.rate <= 0) continue;
        const int64_t dpos = std::max<int64_t>(0, v.pos + (v.lagKnown ? v.lag : 0));
        const int64_t c = splitContaining(dpos * kModelRate / v.rate);
        if (job.split >= c && job.split <= c + 2) return true;
    }
    return false;
}

bool StemEngine::runJob(const Job& job) {
    TrackSlot* slot = job.slot;
    DecodedTrack* dec = slot->decoded.get();
    if (!dec) return false;
    const int R = slot->rate.load();
    const int F = dec->sampleRate();
    const int64_t c = job.split;
    const int64_t spanStart = c * kStepSamples - kPad;
    jobTrack_.store(job.track);
    jobProgress_.store(0.0);

    std::unique_lock<std::mutex> lock(modelMu_);
    if (!separator_ || !separator_->isLoaded()) return false;

    // 1. The split's input at 44.1 kHz.
    if (F == kModelRate) {
        if (!dec->decodeUntil(spanStart + kInputSpan, &quit_)) {
            setReason(job.track, "decode");
            return false;
        }
        dec->read(spanStart, kInputSpan, in44_.data());
    } else {
        const int H = resampler_.halfWidth(F, kModelRate);
        const int64_t fA = floorDiv(spanStart * F, kModelRate) - H;
        const int64_t fB = ceilDiv((spanStart + kInputSpan) * F, kModelRate) + H;
        if (!dec->decodeUntil(fB, &quit_)) {
            setReason(job.track, "decode");
            return false;
        }
        std::vector<float> tmp(size_t(fB - fA) * 2);
        dec->read(fA, fB - fA, tmp.data());
        resampler_.process(tmp.data(), fA, fB - fA, F, in44_.data(), spanStart, kInputSpan, kModelRate);
    }
    if (dec->finished()) slot->lengthR = ceilDiv(dec->framesDecoded() * R, F);

    const int64_t r0 = ownedStartR(c, R);
    const int64_t r1 = ownedEndR(c, R, slot->lengthR);
    if (r1 <= r0) return true;  // past the end of the track
    jobProgress_.store(0.1);

    // 2. Separate.
    std::string err;
    auto progress = [this](double p) { jobProgress_.store(0.1 + 0.8 * p); };
    if (!computeSplit(in44_.data(), &quit_, &err, progress, &job)) return false;

    // 3. Vocals and drums at the playback rate.
    const int64_t n = r1 - r0;
    std::vector<float> outV(size_t(n) * 2), outD(size_t(n) * 2);
    if (R == kModelRate) {
        for (int64_t t = 0; t < n; ++t) {
            const int64_t rel = r0 + t - spanStart;
            outV[size_t(t) * 2] = accVL_[size_t(rel)];
            outV[size_t(t) * 2 + 1] = accVR_[size_t(rel)];
            outD[size_t(t) * 2] = accDL_[size_t(rel)];
            outD[size_t(t) * 2 + 1] = accDR_[size_t(rel)];
        }
    } else {
        std::vector<float> blk(size_t(kInputSpan) * 2);
        for (int64_t i = 0; i < kInputSpan; ++i) {
            blk[size_t(i) * 2] = accVL_[size_t(i)];
            blk[size_t(i) * 2 + 1] = accVR_[size_t(i)];
        }
        resampler_.process(blk.data(), spanStart, kInputSpan, kModelRate, outV.data(), r0, n, R);
        for (int64_t i = 0; i < kInputSpan; ++i) {
            blk[size_t(i) * 2] = accDL_[size_t(i)];
            blk[size_t(i) * 2 + 1] = accDR_[size_t(i)];
        }
        resampler_.process(blk.data(), spanStart, kInputSpan, kModelRate, outD.data(), r0, n, R);
    }
    lock.unlock();

    // 4. The mix at the playback rate — the decoder's own samples when the
    //    rates agree, so 100% on every stem plays the decode bit for bit.
    std::vector<int16_t> mix(size_t(n) * 2);
    if (F == R) {
        dec->decodeUntil(r1, &quit_);
        dec->readI16(r0, n, mix.data());
    } else {
        const int H = resampler_.halfWidth(F, R);
        const int64_t fA = floorDiv(r0 * F, R) - H;
        const int64_t fB = ceilDiv(r1 * F, R) + H;
        dec->decodeUntil(fB, &quit_);
        std::vector<float> tmp(size_t(fB - fA) * 2), mixF(size_t(n) * 2);
        dec->read(fA, fB - fA, tmp.data());
        resampler_.process(tmp.data(), fA, fB - fA, F, mixF.data(), r0, n, R);
        for (size_t i = 0; i < mix.size(); ++i) mix[i] = toI16(mixF[i]);
    }

    // 5. Publish. Keep about one split of history behind the playhead.
    int64_t keepFrom = 0;
    for (const StemTap::View& v : snapshotTaps()) {
        if (v.track != job.track) continue;
        const int64_t dpos = v.pos + (v.lagKnown ? v.lag : 0);
        keepFrom = std::max<int64_t>(keepFrom, dpos - toRate(kStepSamples, R));
    }
    StemStore::Write w = slot->store.beginWrite(r0, r1, keepFrom);
    for (size_t i = 0; i < size_t(n) * 2; ++i) {
        w.mix[i] = mix[i];
        w.v[i] = toI16(outV[i] * StemStore::kStemScale);
        w.d[i] = toI16(outD[i] * StemStore::kStemScale);
    }
    slot->store.endWrite(w);
    jobProgress_.store(1.0);
    return true;
}

bool StemEngine::computeSplit(const float* in44, const std::atomic<bool>* cancel, std::string* error,
                              const std::function<void(double)>& progress, const Job* job) {
    // Requires modelMu_ held by the caller.
    for (int64_t i = 0; i < kInputSpan; ++i) {
        inL_[size_t(i)] = in44[size_t(i) * 2];
        inR_[size_t(i)] = in44[size_t(i) * 2 + 1];
    }
    float* lRe = spec_.data();
    float* lIm = lRe + kSpecBins;
    float* rRe = lIm + kSpecBins;
    float* rIm = rRe + kSpecBins;

    // Pass 1: magnitudes of the lowest kNetBins bins.
    for (int j = 0; j < kSplitFrames; ++j) {
        stft_->forward(&inL_[size_t(j) * kHop], &inR_[size_t(j) * kHop], lRe, lIm, rRe, rIm);
        float* mL = &mag_[size_t(j) * kNetBins];
        float* mR = &mag_[size_t(kSplitFrames + j) * kNetBins];
        for (int k = 0; k < kNetBins; ++k) {
            mL[k] = std::sqrt(lRe[k] * lRe[k] + lIm[k] * lIm[k]);
            mR[k] = std::sqrt(rRe[k] * rRe[k] + rIm[k] * rIm[k]);
        }
    }
    if (progress) progress(0.1);

    auto runNet = [&](int net, float* out) {
        if (cancel && cancel->load()) {
            if (error) *error = "cancelled";
            return false;
        }
        if (job && !stillWanted(*job)) {
            if (error) *error = "superseded";
            return false;
        }
        return separator_->run(net, mag_.data(), out, error);
    };

    // The soft ratio mask needs all four estimates: sum of squares first.
    if (!runNet(kNetVocals, eV_.data())) return false;
    if (progress) progress(0.3);
    if (!runNet(kNetDrums, eD_.data())) return false;
    if (progress) progress(0.5);
    if (!runNet(kNetBass, tmp_.data())) return false;
    for (int i = 0; i < kBins; ++i) sum_[i] = eV_[i] * eV_[i] + eD_[i] * eD_[i] + tmp_[i] * tmp_[i];
    if (progress) progress(0.7);
    if (!runNet(kNetOther, tmp_.data())) return false;
    for (int i = 0; i < kBins; ++i) {
        const float total = sum_[i] + tmp_[i] * tmp_[i] + 1e-10f;
        eV_[i] = (eV_[i] * eV_[i] + 2.5e-11f) / total;  // masks, in place
        eD_[i] = (eD_[i] * eD_[i] + 2.5e-11f) / total;
    }
    for (int row = 0; row < 2 * kSplitFrames; ++row) {
        double sv = 0.0, sd = 0.0;
        const float* mv = &eV_[size_t(row) * kNetBins];
        const float* md = &eD_[size_t(row) * kNetBins];
        for (int k = 0; k < kNetBins; ++k) {
            sv += mv[k];
            sd += md[k];
        }
        avgV_[size_t(row)] = float(sv / kNetBins);
        avgD_[size_t(row)] = float(sd / kNetBins);
    }
    if (progress) progress(0.85);

    // Pass 2: apply the masks to the original complex spectra and overlap-add.
    std::fill(accVL_.begin(), accVL_.end(), 0.0f);
    std::fill(accVR_.begin(), accVR_.end(), 0.0f);
    std::fill(accDL_.begin(), accDL_.end(), 0.0f);
    std::fill(accDR_.begin(), accDR_.end(), 0.0f);
    float* vlRe = rIm + kSpecBins;
    float* vlIm = vlRe + kSpecBins;
    float* vrRe = vlIm + kSpecBins;
    float* vrIm = vrRe + kSpecBins;
    float* dlRe = vrIm + kSpecBins;
    float* dlIm = dlRe + kSpecBins;
    float* drRe = dlIm + kSpecBins;
    float* drIm = drRe + kSpecBins;
    float* fVL = drIm + kSpecBins;
    float* fVR = fVL + kNfft;
    float* fDL = fVR + kNfft;
    float* fDR = fDL + kNfft;
    for (int j = 0; j < kSplitFrames; ++j) {
        stft_->forward(&inL_[size_t(j) * kHop], &inR_[size_t(j) * kHop], lRe, lIm, rRe, rIm);
        const float* mvL = &eV_[size_t(j) * kNetBins];
        const float* mvR = &eV_[size_t(kSplitFrames + j) * kNetBins];
        const float* mdL = &eD_[size_t(j) * kNetBins];
        const float* mdR = &eD_[size_t(kSplitFrames + j) * kNetBins];
        const float avL = avgV_[size_t(j)], avR = avgV_[size_t(kSplitFrames + j)];
        const float adL = avgD_[size_t(j)], adR = avgD_[size_t(kSplitFrames + j)];
        for (int k = 0; k < kSpecBins; ++k) {
            const bool net = k < kNetBins;
            const float gvl = net ? mvL[k] : avL, gvr = net ? mvR[k] : avR;
            const float gdl = net ? mdL[k] : adL, gdr = net ? mdR[k] : adR;
            vlRe[k] = lRe[k] * gvl; vlIm[k] = lIm[k] * gvl;
            vrRe[k] = rRe[k] * gvr; vrIm[k] = rIm[k] * gvr;
            dlRe[k] = lRe[k] * gdl; dlIm[k] = lIm[k] * gdl;
            drRe[k] = rRe[k] * gdr; drIm[k] = rIm[k] * gdr;
        }
        stft_->inverse(vlRe, vlIm, vrRe, vrIm, fVL, fVR);
        stft_->inverse(dlRe, dlIm, drRe, drIm, fDL, fDR);
        float* aVL = &accVL_[size_t(j) * kHop];
        float* aVR = &accVR_[size_t(j) * kHop];
        float* aDL = &accDL_[size_t(j) * kHop];
        float* aDR = &accDR_[size_t(j) * kHop];
        for (int t = 0; t < kNfft; ++t) {
            aVL[t] += fVL[t];
            aVR[t] += fVR[t];
            aDL[t] += fDL[t];
            aDR[t] += fDR[t];
        }
    }
    const float norm = 1.0f / StereoStft::kOlaGain;
    for (int64_t i = 0; i < kInputSpan; ++i) {
        accVL_[size_t(i)] *= norm;
        accVR_[size_t(i)] *= norm;
        accDL_[size_t(i)] *= norm;
        accDR_[size_t(i)] *= norm;
    }
    if (progress) progress(1.0);
    return true;
}

void StemEngine::cleanup(const std::vector<StemTap::View>& views, int64_t now, bool wanted) {
    const bool idleTooLong = !wanted && now - lastWantedMs_.load() > kIdleReleaseMs;
    for (TrackSlot& s : pool_) {
        const uint32_t id = s.id.load(std::memory_order_relaxed);
        if (id == 0) {
            if (s.needsFree && now - s.retiredMs >= kQuiesceMs) freeSlot(&s);
            continue;
        }
        bool referenced = false;
        for (const StemTap::View& v : views) referenced = referenced || v.track == id || v.next == id;
        if (referenced) s.lastUsedMs = now;
        // A track can become off limits after it was separated (the app's
        // YouTube list arrives late): stop mixing it at once.
        const bool barred = !trackInfo(id).reason.empty();
        if (barred || idleTooLong || now - s.lastUsedMs > kUnusedReleaseMs) {
            s.id.store(0, std::memory_order_release);
            s.retiredMs = now;
            s.needsFree = true;
        }
    }
}

// ---- Status ------------------------------------------------------------------

void StemEngine::publishStatus(const std::vector<StemTap::View>& views, int64_t now, bool wanted) {
    const StemTap::View* fg = nullptr;
    for (const StemTap::View& v : views) {
        const bool playing = v.lastProcessMs > 0 && now - v.lastProcessMs < kPlayingWindowMs;
        if (!playing || v.track == 0) continue;
        if (!fg || v.trackStartMs > fg->trackStartMs) fg = &v;
    }

    StemStatus st;
    if (fg) {
        const TrackInfo info = trackInfo(fg->track);
        st.trackKey = info.key;
        if (!info.reason.empty()) {
            st.state = "unavailable";
            st.reason = info.reason;
        } else if (!modelLoaded_.load()) {
            st.state = wanted ? "unavailable" : "idle";
            st.reason = "model";
        } else if (!wanted) {
            st.state = "idle";
        } else {
            TrackSlot* slot = slotFor(fg->track, fg->rate, false, views, now);
            const int64_t dpos = fg->pos + (fg->lagKnown ? fg->lag : 0);
            if (slot && fg->lagKnown && slot->store.covers(dpos, dpos + 1)) {
                st.state = "ready";
                st.progress = 1.0;
                st.aheadSeconds = double(slot->store.readyUntil(dpos) - dpos) / double(fg->rate);
            } else {
                st.state = "preparing";
                st.progress = jobTrack_.load() == fg->track ? jobProgress_.load() : 0.0;
            }
        }
    }

    std::function<void(const StemStatus&)> cb;
    {
        std::lock_guard<std::mutex> lock(statusMu_);
        const bool stateChanged = st.state != status_.state || st.reason != status_.reason ||
                                  st.trackKey != status_.trackKey;
        if (status_.sameAs(st) || (!stateChanged && now - lastEmitMs_ < 250)) return;
        status_ = st;
        lastEmitMs_ = now;
        cb = statusCb_;
    }
    if (cb) cb(st);
}

void StemEngine::setStatusCallback(std::function<void(const StemStatus&)> cb) {
    std::lock_guard<std::mutex> lock(statusMu_);
    statusCb_ = std::move(cb);
}

StemStatus StemEngine::status() const {
    std::lock_guard<std::mutex> lock(statusMu_);
    return status_;
}

}  // namespace stems
}  // namespace hype
