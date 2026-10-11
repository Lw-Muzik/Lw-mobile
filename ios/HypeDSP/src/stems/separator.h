#pragma once
// Model interface for the stem engine. Spleeter is the shipped model; this
// boundary is where a better one (SCNet, a commercial SDK) would slot in.

#include "stem_config.h"

#include <atomic>
#include <memory>
#include <string>

namespace hype {
namespace stems {

class Separator {
public:
    virtual ~Separator() = default;

    // Loads vocals.onnx, drums.onnx, bass.onnx and other.onnx from `dir`.
    virtual bool load(const std::string& dir, std::string* error) = 0;
    virtual bool isLoaded() const = 0;
    virtual void unload() = 0;

    // Runs net `net` (NetIndex) on one split of magnitudes laid out
    // [2 channels][kSplitFrames][kNetBins] and writes that stem's magnitude
    // estimate (same layout) to `out`. Worker thread only.
    virtual bool run(int net, const float* mag, float* out, std::string* error) = 0;
};

// Spleeter 4-stem via ONNX Runtime (CPU). `threads` = intra-op threads.
std::unique_ptr<Separator> createSpleeterOnnx(int threads);

}  // namespace stems
}  // namespace hype
