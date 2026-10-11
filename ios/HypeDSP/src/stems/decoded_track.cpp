#include "decoded_track.h"

#include <algorithm>
#include <cstring>
#include <fcntl.h>
#include <unistd.h>

namespace hype {
namespace stems {

namespace {
constexpr int kChunkFrames = 8192;
}

DecodedTrack::DecodedTrack(std::string cachePath) : path_(std::move(cachePath)) {}

DecodedTrack::~DecodedTrack() {
    source_.reset();
    if (fd_ >= 0) {
        ::close(fd_);
        ::unlink(path_.c_str());
    }
}

bool DecodedTrack::begin(std::unique_ptr<PcmSource> source, std::string* reason) {
    source_ = std::move(source);
    if (!source_ || !source_->open(reason)) {
        failed_ = true;
        if (reason && reason->empty()) *reason = "decode";
        return false;
    }
    const PcmFormat f = source_->format();
    sampleRate_ = f.sampleRate;
    durationEstimate_ = f.durationFrames;
    if (sampleRate_ <= 0) {
        failed_ = true;
        if (reason) *reason = "unsupported";
        return false;
    }
    fd_ = ::open(path_.c_str(), O_RDWR | O_CREAT | O_TRUNC, 0600);
    if (fd_ < 0) {
        failed_ = true;
        if (reason) *reason = "decode";
        return false;
    }
    chunk_.resize(size_t(kChunkFrames) * 2);
    return true;
}

bool DecodedTrack::decodeUntil(int64_t target, const std::atomic<bool>* cancel) {
    if (failed_) return false;
    while (!finished_ && frames_ < target) {
        if (cancel && cancel->load(std::memory_order_relaxed)) return true;
        const int got = source_->read(chunk_.data(), kChunkFrames);
        if (got < 0) {
            failed_ = true;
            return false;
        }
        if (got == 0) {
            finished_ = true;
            source_.reset();  // release the decoder (and its file) early
            break;
        }
        const size_t bytes = size_t(got) * 2 * sizeof(int16_t);
        const off_t at = off_t(frames_) * 2 * off_t(sizeof(int16_t));
        if (::pwrite(fd_, chunk_.data(), bytes, at) != ssize_t(bytes)) {
            failed_ = true;
            return false;
        }
        frames_ += got;
    }
    return true;
}

void DecodedTrack::readI16(int64_t start, int64_t count, int16_t* out) {
    std::memset(out, 0, size_t(count) * 2 * sizeof(int16_t));
    const int64_t a = std::max<int64_t>(start, 0);
    const int64_t b = std::min<int64_t>(start + count, frames_);
    if (b <= a || fd_ < 0) return;
    const size_t bytes = size_t(b - a) * 2 * sizeof(int16_t);
    const off_t at = off_t(a) * 2 * off_t(sizeof(int16_t));
    int16_t* dst = out + (a - start) * 2;
    size_t done = 0;
    while (done < bytes) {
        const ssize_t n = ::pread(fd_, reinterpret_cast<char*>(dst) + done, bytes - done,
                                  at + off_t(done));
        if (n <= 0) break;
        done += size_t(n);
    }
}

void DecodedTrack::read(int64_t start, int64_t count, float* out) {
    std::vector<int16_t> tmp(size_t(count) * 2);
    readI16(start, count, tmp.data());
    const float k = 1.0f / 32768.0f;
    for (size_t i = 0; i < tmp.size(); ++i) out[i] = float(tmp[i]) * k;
}

}  // namespace stems
}  // namespace hype
