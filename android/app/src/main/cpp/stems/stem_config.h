#pragma once
// Live stem separation — shared constants.
//
// CANONICAL COPY: android/app/src/main/cpp/stems/. The iOS pod carries a
// byte-identical copy in ios/HypeDSP/src/stems/ — edit here, then run
// tool/sync_stems_native.sh (CI-style check: tool/sync_stems_native.sh --check).
//
// The numbers below are Spleeter's training-time STFT contract (see the model
// card of Best-Practice/spleeter-4stems-onnx): periodic Hann, 4096-point
// frames, hop 1024, 44.1 kHz stereo. The nets see the lowest 1024 of the 2049
// bins (~11 kHz); masks above that are extended with the per-frame mean
// ("average" extension), which keeps the stems summing exactly to the mix.

#include <cstdint>

namespace hype {
namespace stems {

constexpr int kModelRate = 44100;
constexpr int kNfft = 4096;
constexpr int kHop = 1024;
constexpr int kSpecBins = kNfft / 2 + 1;  // 2049
constexpr int kNetBins = 1024;
constexpr int kSplitFrames = 512;         // frames per net run (fixed by the graph)
constexpr int kPad = kNfft - kHop;        // 3072: frame f starts at f*kHop - kPad

// Every sample is covered by kNfft/kHop = 4 frames, so a split can finalise
// only the samples whose 4 frames all lie inside it.
constexpr int kFinalFrames = kSplitFrames - (kNfft / kHop - 1);  // 509
constexpr int64_t kFinalSpan = int64_t(kFinalFrames) * kHop;     // 521216

// Consecutive splits overlap by 4 frames. Each split then *owns* a range with
// kMargin samples of exact output on both sides — room for the resampler
// taps when playback runs at a rate other than 44.1 kHz — and splits can be
// computed in any order (a seek just starts at a different split).
constexpr int kStepFrames = kSplitFrames - 4;                   // 508
constexpr int64_t kStepSamples = int64_t(kStepFrames) * kHop;  // 520192 (~11.8 s)
constexpr int kMargin = 512;

// Input samples a split needs: [c*kStepSamples - kPad, c*kStepSamples + kInputSpan).
constexpr int64_t kInputSpan = int64_t(kSplitFrames) * kHop + kPad;  // 527360

constexpr int kNetCount = 4;
enum NetIndex { kNetVocals = 0, kNetDrums = 1, kNetBass = 2, kNetOther = 3 };

// Owned range of split c in the model (44.1 kHz) domain.
inline int64_t splitOwnedStart(int64_t c) { return c == 0 ? 0 : c * kStepSamples + kMargin; }
inline int64_t splitOwnedEnd(int64_t c) { return (c + 1) * kStepSamples + kMargin; }
inline int64_t splitContaining(int64_t modelSample) {
    if (modelSample < splitOwnedEnd(0)) return 0;
    return (modelSample - kMargin) / kStepSamples;
}

// A split can also start anywhere: after a seek the engine starts one where the
// playhead will be by the time it is ready, and each next one where the last
// ended. One starting at model sample s owns [s, chunkOwnedEnd(s)) and reads
// the span [chunkSpanStart(s), +kInputSpan), the same layout split c has (for
// s == splitOwnedStart(c) these are exactly split c's).
inline int64_t chunkOwnedEnd(int64_t s) { return s == 0 ? splitOwnedEnd(0) : s + kStepSamples; }
inline int64_t chunkSpanStart(int64_t s) { return s == 0 ? -kPad : s - kMargin - kPad; }

// Map a model-domain boundary to a playback-rate boundary (floor). Monotonic,
// so ranges [b(c), b(c+1)) tile the playback timeline with no gaps.
inline int64_t toRate(int64_t modelSample, int rate) {
    return rate == kModelRate ? modelSample : (modelSample * rate) / kModelRate;
}

// The reverse, also floor: toRate(fromRate(r, rate), rate) <= r, so a chunk
// started at fromRate(end of what is ready) overlaps it by a sample at most and
// never leaves a hole.
inline int64_t fromRate(int64_t r, int rate) {
    return rate == kModelRate ? r : (r * kModelRate) / rate;
}

}  // namespace stems
}  // namespace hype
