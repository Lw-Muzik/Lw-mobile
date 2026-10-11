#pragma once
// PcmSource implementations for the host tests: an in-memory buffer and a WAV
// file reader (16-bit PCM or 32-bit float, mono or stereo).

#include "pcm_source.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

namespace stemtest {

using hype::stems::PcmFormat;
using hype::stems::PcmSource;

class MemorySource : public PcmSource {
public:
    MemorySource(std::vector<float> interleaved, int rate) : data_(std::move(interleaved)), rate_(rate) {}
    bool open(std::string*) override { return true; }
    PcmFormat format() const override {
        PcmFormat f;
        f.sampleRate = rate_;
        f.durationFrames = int64_t(data_.size() / 2);
        return f;
    }
    int read(int16_t* dst, int maxFrames) override {
        const int64_t total = int64_t(data_.size() / 2);
        const int n = int(std::min<int64_t>(maxFrames, total - pos_));
        for (int i = 0; i < n * 2; ++i) {
            const float s = std::max(-1.0f, std::min(1.0f, data_[size_t(pos_ * 2 + i)]));
            dst[i] = int16_t(std::lrintf(s * 32767.0f));
        }
        pos_ += n;
        return n;
    }

private:
    std::vector<float> data_;
    int rate_;
    int64_t pos_ = 0;
};

// Minimal RIFF/WAVE reader into float stereo.
inline bool readWav(const std::string& path, std::vector<float>* out, int* rate) {
    FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) return false;
    std::vector<uint8_t> buf;
    uint8_t chunk[65536];
    size_t n;
    while ((n = std::fread(chunk, 1, sizeof chunk, f)) > 0) buf.insert(buf.end(), chunk, chunk + n);
    std::fclose(f);
    if (buf.size() < 12 || std::memcmp(buf.data(), "RIFF", 4) || std::memcmp(buf.data() + 8, "WAVE", 4)) return false;
    size_t p = 12;
    int fmt = 0, channels = 0, bits = 0;
    while (p + 8 <= buf.size()) {
        uint32_t size;
        std::memcpy(&size, buf.data() + p + 4, 4);
        const uint8_t* body = buf.data() + p + 8;
        if (!std::memcmp(buf.data() + p, "fmt ", 4)) {
            uint16_t f16;
            std::memcpy(&f16, body, 2);
            fmt = f16;
            std::memcpy(&f16, body + 2, 2);
            channels = f16;
            uint32_t sr;
            std::memcpy(&sr, body + 4, 4);
            *rate = int(sr);
            std::memcpy(&f16, body + 14, 2);
            bits = f16;
            if (fmt == 0xFFFE && size >= 26) {  // WAVE_FORMAT_EXTENSIBLE: sub-format
                std::memcpy(&f16, body + 24, 2);
                fmt = f16;
            }
        } else if (!std::memcmp(buf.data() + p, "data", 4)) {
            const size_t frames = size / size_t(channels * bits / 8);
            out->assign(frames * 2, 0.0f);
            for (size_t i = 0; i < frames; ++i) {
                for (int c = 0; c < 2; ++c) {
                    const int src = std::min(c, channels - 1);
                    const uint8_t* s = body + (i * channels + src) * (bits / 8);
                    float v = 0.0f;
                    if (fmt == 1 && bits == 16) {
                        int16_t x;
                        std::memcpy(&x, s, 2);
                        v = float(x) / 32768.0f;
                    } else if (fmt == 3 && bits == 32) {
                        std::memcpy(&v, s, 4);
                    } else {
                        return false;
                    }
                    (*out)[i * 2 + c] = v;
                }
            }
            return true;
        }
        p += 8 + size + (size & 1);
    }
    return false;
}

}  // namespace stemtest
