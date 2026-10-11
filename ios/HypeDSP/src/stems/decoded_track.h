#pragma once
// The decoded audio of one track, kept in a cache file rather than RAM.
//
// A 4-minute song is ~42 MB of 16-bit stereo; a 10-minute one ~106 MB. The
// worker decodes sequentially (fast: decoders run at 100x+ real time) and
// reads back whatever split it needs with pread(). Sequential decoding also
// gives one self-consistent sample timeline — seeking a VBR MP3 decoder per
// split would put every split on a slightly different clock.

#include "pcm_source.h"

#include <atomic>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace hype {
namespace stems {

class DecodedTrack {
public:
    explicit DecodedTrack(std::string cachePath);
    ~DecodedTrack();
    DecodedTrack(const DecodedTrack&) = delete;
    DecodedTrack& operator=(const DecodedTrack&) = delete;

    // Opens the source and the cache file. On failure `reason` is set.
    bool begin(std::unique_ptr<PcmSource> source, std::string* reason);

    int sampleRate() const { return sampleRate_; }
    int64_t framesDecoded() const { return frames_; }
    bool finished() const { return finished_; }
    bool failed() const { return failed_; }
    int64_t durationEstimate() const { return durationEstimate_; }

    // Decodes until at least `target` frames exist, the source ends, or
    // `cancel` is raised. Returns false on a decode error.
    bool decodeUntil(int64_t target, const std::atomic<bool>* cancel);

    // Reads frames [start, start + count) as float stereo interleaved. Frames
    // outside the decoded range read as silence.
    void read(int64_t start, int64_t count, float* out);
    // Same, as raw int16 (exact copy of what the decoder produced).
    void readI16(int64_t start, int64_t count, int16_t* out);

private:
    std::string path_;
    int fd_ = -1;
    std::unique_ptr<PcmSource> source_;
    int sampleRate_ = 0;
    int64_t frames_ = 0;
    int64_t durationEstimate_ = -1;
    bool finished_ = false;
    bool failed_ = false;
    std::vector<int16_t> chunk_;
};

}  // namespace stems
}  // namespace hype
