#pragma once
// Separated audio for one track at the playback rate, in a few fixed slots.
//
// One slot holds one split's owned range (~11.8 s): the decoded mix exactly as
// the decoder produced it, plus vocals and drums. Instruments are derived at
// mix time as mix - vocals - drums, so with every level at 100% the output is
// the decoded mix bit for bit.
//
// Threading: ONE writer (the engine worker) and lock-free readers (audio
// threads). Each slot is a seqlock: the writer makes `seq` odd while it
// rewrites a slot and even when the slot is published; a reader that sees the
// sequence change during its copy throws the copy away and plays the original
// audio for that buffer instead. Buffers are allocated the first time a slot
// is used — before it was ever readable — and never reallocated afterwards.

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <vector>

namespace hype {
namespace stems {

class StemStore {
public:
    static constexpr int kSlots = 4;  // ~1 split behind, current, 2 ahead

    // Vocals/drums are stored at half scale so the int16 range has 6 dB of
    // headroom: a stem can momentarily peak above the mix it came from.
    static constexpr float kStemScale = 0.5f;

    // Worker: set the capacity (frames) of every slot. Only while no reader
    // can reach this store.
    void configure(int64_t slotFrames) {
        capacity_ = slotFrames;
        for (Slot& s : slots_) {
            s.seq.store(0, std::memory_order_relaxed);
            s.start.store(0, std::memory_order_relaxed);
            s.end.store(0, std::memory_order_relaxed);
            std::vector<int16_t>().swap(s.mix);
            std::vector<int16_t>().swap(s.v);
            std::vector<int16_t>().swap(s.d);
        }
    }

    int64_t capacity() const { return capacity_; }

    // Worker: forget all published ranges (readers see them vanish).
    void invalidate() {
        for (Slot& s : slots_) {
            s.seq.fetch_add(1, std::memory_order_acq_rel);
            s.start.store(0, std::memory_order_relaxed);
            s.end.store(0, std::memory_order_relaxed);
            s.seq.fetch_add(1, std::memory_order_release);
        }
    }

    struct Write {
        int slot = -1;
        int16_t* mix = nullptr;
        int16_t* v = nullptr;
        int16_t* d = nullptr;
    };

    // Worker: claim a slot for [start, end). Prefers an empty slot, then the
    // one that ends furthest behind `keepFrom` (the reader's position minus
    // the history worth keeping), then the one furthest ahead of it.
    Write beginWrite(int64_t start, int64_t end, int64_t keepFrom) {
        int pick = -1;
        for (int i = 0; i < kSlots; ++i) {
            if (slots_[i].end.load(std::memory_order_relaxed) <= slots_[i].start.load(std::memory_order_relaxed)) {
                pick = i;
                break;
            }
        }
        if (pick < 0) {
            int64_t bestEnd = INT64_MAX;
            for (int i = 0; i < kSlots; ++i) {
                const int64_t e = slots_[i].end.load(std::memory_order_relaxed);
                if (e <= keepFrom && e < bestEnd) { bestEnd = e; pick = i; }
            }
        }
        if (pick < 0) {
            int64_t bestStart = INT64_MIN;
            for (int i = 0; i < kSlots; ++i) {
                const int64_t s = slots_[i].start.load(std::memory_order_relaxed);
                if (s > bestStart) { bestStart = s; pick = i; }
            }
        }
        Slot& s = slots_[pick];
        s.seq.fetch_add(1, std::memory_order_acq_rel);  // odd: readers skip it
        const size_t need = size_t(std::max<int64_t>(capacity_, end - start)) * 2;
        if (s.mix.size() < need) {
            // Only reachable for a slot that was never published at this size;
            // see the class comment.
            s.mix.resize(need);
            s.v.resize(need);
            s.d.resize(need);
        }
        s.pendingStart = start;
        s.pendingEnd = end;
        Write w;
        w.slot = pick;
        w.mix = s.mix.data();
        w.v = s.v.data();
        w.d = s.d.data();
        return w;
    }

    void endWrite(const Write& w) {
        Slot& s = slots_[w.slot];
        s.start.store(s.pendingStart, std::memory_order_relaxed);
        s.end.store(s.pendingEnd, std::memory_order_relaxed);
        s.seq.fetch_add(1, std::memory_order_release);  // even: published
    }

    // Worker: true when [start, end) is entirely inside published slots.
    bool covers(int64_t start, int64_t end) const {
        int64_t at = start;
        for (int guard = 0; guard < kSlots && at < end; ++guard) {
            bool advanced = false;
            for (const Slot& s : slots_) {
                const int64_t a = s.start.load(std::memory_order_relaxed);
                const int64_t b = s.end.load(std::memory_order_relaxed);
                if (b > a && at >= a && at < b) { at = b; advanced = true; break; }
            }
            if (!advanced) break;
        }
        return at >= end;
    }

    // Worker: end of the contiguous published run starting at `from`
    // (== from when `from` itself is not published).
    int64_t readyUntil(int64_t from) const {
        int64_t at = from;
        for (int guard = 0; guard < kSlots; ++guard) {
            bool advanced = false;
            for (const Slot& s : slots_) {
                const int64_t a = s.start.load(std::memory_order_relaxed);
                const int64_t b = s.end.load(std::memory_order_relaxed);
                if (b > a && at >= a && at < b) { at = b; advanced = true; break; }
            }
            if (!advanced) break;
        }
        return at;
    }

    // Audio thread: copies up to `count` frames starting at `pos` from ONE
    // slot into float stereo buffers. Returns the frames copied (0 when `pos`
    // is not published or the slot changed mid-copy). Call again at
    // pos + returned to continue into the next slot.
    int read(int64_t pos, int count, float* mix, float* v, float* d) const {
        constexpr float kMix = 1.0f / 32768.0f;
        constexpr float kStem = 1.0f / (32768.0f * kStemScale);
        for (const Slot& s : slots_) {
            const uint32_t q = s.seq.load(std::memory_order_acquire);
            if (q & 1u) continue;
            const int64_t a = s.start.load(std::memory_order_relaxed);
            const int64_t b = s.end.load(std::memory_order_relaxed);
            if (b <= a || pos < a || pos >= b) continue;
            const int n = int(std::min<int64_t>(count, b - pos));
            const size_t off = size_t(pos - a) * 2;
            const int16_t* pm = s.mix.data() + off;
            const int16_t* pv = s.v.data() + off;
            const int16_t* pd = s.d.data() + off;
            for (int i = 0; i < n * 2; ++i) {
                mix[i] = float(pm[i]) * kMix;
                v[i] = float(pv[i]) * kStem;
                d[i] = float(pd[i]) * kStem;
            }
            std::atomic_thread_fence(std::memory_order_acquire);
            if (s.seq.load(std::memory_order_relaxed) != q) return 0;
            return n;
        }
        return 0;
    }

private:
    struct Slot {
        std::atomic<uint32_t> seq{0};
        std::atomic<int64_t> start{0};
        std::atomic<int64_t> end{0};
        int64_t pendingStart = 0;
        int64_t pendingEnd = 0;
        std::vector<int16_t> mix, v, d;
    };
    Slot slots_[kSlots];
    int64_t capacity_ = 0;
};

}  // namespace stems
}  // namespace hype
