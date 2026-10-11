#pragma once
// iOS decoder for the stem engine: AVAssetReader over a local asset URL
// (file:// or ipod-library://). Protected (DRM) items are reported as such.

#include "stems/pcm_source.h"

#include <memory>
#include <string>

namespace hype {
namespace stems {

std::unique_ptr<PcmSource> createAvPcmSource(const std::string& url);

}  // namespace stems
}  // namespace hype
