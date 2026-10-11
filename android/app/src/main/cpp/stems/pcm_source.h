#pragma once
// A sequential decoder for one local audio file, implemented per platform
// (Android: NDK MediaExtractor/MediaCodec; iOS: AVAssetReader; host tests:
// a WAV reader). The engine owns it on its worker thread.

#include <cstdint>
#include <functional>
#include <memory>
#include <string>

namespace hype {
namespace stems {

struct PcmFormat {
    int sampleRate = 0;
    int64_t durationFrames = -1;  // -1 when unknown
};

class PcmSource {
public:
    virtual ~PcmSource() = default;

    // Opens the file and reads its format. On failure `reason` is one of the
    // status reasons ("protected", "unsupported", "decode").
    virtual bool open(std::string* reason) = 0;
    virtual PcmFormat format() const = 0;

    // Decodes the next frames as interleaved int16 STEREO (mono is duplicated,
    // extra channels dropped). Returns frames written, 0 at end, -1 on error.
    virtual int read(int16_t* dst, int maxFrames) = 0;
};

using PcmSourceFactory = std::function<std::unique_ptr<PcmSource>()>;

}  // namespace stems
}  // namespace hype
