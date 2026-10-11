#pragma once
// Android decoder for the stem engine: NDK MediaExtractor + MediaCodec.
//
// The same platform decoders ExoPlayer's MediaCodec renderer uses, so the
// engine's copy of a track matches the player's samples (the engine still
// aligns the two by correlation; see stems/align.h).

#include "stems/pcm_source.h"

#include <cstdint>
#include <memory>
#include <string>

namespace hype {
namespace stems {

// `path`: a local file path, or empty with `fd` >= 0 (owned and closed here,
// e.g. from ContentResolver for content:// URIs).
std::unique_ptr<PcmSource> createNdkPcmSource(const std::string& path, int fd);

}  // namespace stems
}  // namespace hype
