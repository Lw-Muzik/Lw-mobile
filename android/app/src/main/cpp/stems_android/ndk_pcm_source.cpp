#include "ndk_pcm_source.h"

#include <android/log.h>
#include <fcntl.h>
#include <media/NdkMediaCodec.h>
#include <media/NdkMediaExtractor.h>
#include <media/NdkMediaFormat.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <cstring>
#include <vector>

#define STEMS_LOG_TAG "HypeStems"
#define SLOGW(...) __android_log_print(ANDROID_LOG_WARN, STEMS_LOG_TAG, __VA_ARGS__)

namespace hype {
namespace stems {
namespace {

constexpr int kEncodingPcm16 = 2;     // AudioFormat.ENCODING_PCM_16BIT
constexpr int kEncodingPcmFloat = 4;  // AudioFormat.ENCODING_PCM_FLOAT
constexpr int64_t kTimeoutUs = 5000;

class NdkPcmSource final : public PcmSource {
public:
    NdkPcmSource(std::string path, int fd) : path_(std::move(path)), fd_(fd) {}

    ~NdkPcmSource() override {
        if (codec_) {
            AMediaCodec_stop(codec_);
            AMediaCodec_delete(codec_);
        }
        if (extractor_) AMediaExtractor_delete(extractor_);
        if (fd_ >= 0) ::close(fd_);
    }

    bool open(std::string* reason) override {
        if (fd_ < 0) fd_ = ::open(path_.c_str(), O_RDONLY | O_CLOEXEC);
        if (fd_ < 0) {
            *reason = "decode";
            return false;
        }
        struct stat st {};
        if (fstat(fd_, &st) != 0) {
            *reason = "decode";
            return false;
        }
        // YouTube's audio downloads are MP4 with the "dash" brand. A backstop
        // for the app's own exclusion list: its policy forbids separating them.
        unsigned char head[12] = {};
        if (::pread(fd_, head, sizeof head, 0) == ssize_t(sizeof head) &&
            std::memcmp(head + 4, "ftypdash", 8) == 0) {
            *reason = "youtube";
            return false;
        }
        extractor_ = AMediaExtractor_new();
        if (AMediaExtractor_setDataSourceFd(extractor_, fd_, 0, st.st_size) != AMEDIA_OK) {
            *reason = "unsupported";
            return false;
        }
        if (AMediaExtractor_getPsshInfo(extractor_) != nullptr) {
            *reason = "protected";
            return false;
        }
        const size_t tracks = AMediaExtractor_getTrackCount(extractor_);
        AMediaFormat* format = nullptr;
        const char* mime = nullptr;
        for (size_t i = 0; i < tracks; ++i) {
            AMediaFormat* f = AMediaExtractor_getTrackFormat(extractor_, i);
            const char* m = nullptr;
            if (AMediaFormat_getString(f, AMEDIAFORMAT_KEY_MIME, &m) && m && std::strncmp(m, "audio/", 6) == 0) {
                AMediaExtractor_selectTrack(extractor_, i);
                format = f;
                mime = m;
                break;
            }
            AMediaFormat_delete(f);
        }
        if (!format) {
            *reason = "unsupported";
            return false;
        }
        int32_t sr = 0, ch = 0;
        int64_t durUs = 0;
        AMediaFormat_getInt32(format, AMEDIAFORMAT_KEY_SAMPLE_RATE, &sr);
        AMediaFormat_getInt32(format, AMEDIAFORMAT_KEY_CHANNEL_COUNT, &ch);
        AMediaFormat_getInt64(format, AMEDIAFORMAT_KEY_DURATION, &durUs);
        codec_ = AMediaCodec_createDecoderByType(mime);
        if (!codec_ || AMediaCodec_configure(codec_, format, nullptr, nullptr, 0) != AMEDIA_OK ||
            AMediaCodec_start(codec_) != AMEDIA_OK) {
            AMediaFormat_delete(format);
            *reason = "unsupported";
            return false;
        }
        AMediaFormat_delete(format);
        rate_ = sr;
        channels_ = std::max(1, int(ch));
        // Decode until the first output so the format we report is the one
        // the decoder actually produces (HE-AAC doubles its rate, for one).
        while (available() == 0 && !outputEnded_) {
            if (!pump()) {
                *reason = "decode";
                return false;
            }
        }
        if (rate_ <= 0) {
            *reason = "unsupported";
            return false;
        }
        format_.sampleRate = rate_;
        format_.durationFrames = durUs > 0 ? durUs * rate_ / 1000000 : -1;
        return true;
    }

    PcmFormat format() const override { return format_; }

    int read(int16_t* dst, int maxFrames) override {
        while (available() < size_t(maxFrames) * 2 && !outputEnded_) {
            if (!pump()) return -1;
        }
        const int frames = int(std::min(available() / 2, size_t(maxFrames)));
        std::memcpy(dst, pending_.data() + head_, size_t(frames) * 2 * sizeof(int16_t));
        head_ += size_t(frames) * 2;
        if (head_ > 1 << 16 && head_ * 2 > pending_.size()) {  // compact now and then
            pending_.erase(pending_.begin(), pending_.begin() + long(head_));
            head_ = 0;
        }
        return frames;
    }

private:
    size_t available() const { return pending_.size() - head_; }

    // One round of feeding input and draining output. False on error.
    bool pump() {
        if (!inputEnded_) {
            const ssize_t in = AMediaCodec_dequeueInputBuffer(codec_, kTimeoutUs);
            if (in >= 0) {
                size_t cap = 0;
                uint8_t* buf = AMediaCodec_getInputBuffer(codec_, size_t(in), &cap);
                const ssize_t size = buf ? AMediaExtractor_readSampleData(extractor_, buf, cap) : -1;
                if (size < 0) {
                    AMediaCodec_queueInputBuffer(codec_, size_t(in), 0, 0, 0,
                                                 AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM);
                    inputEnded_ = true;
                } else {
                    const int64_t t = AMediaExtractor_getSampleTime(extractor_);
                    AMediaCodec_queueInputBuffer(codec_, size_t(in), 0, size_t(size), uint64_t(std::max<int64_t>(t, 0)), 0);
                    AMediaExtractor_advance(extractor_);
                }
            }
        }
        AMediaCodecBufferInfo info;
        const ssize_t out = AMediaCodec_dequeueOutputBuffer(codec_, &info, kTimeoutUs);
        if (out >= 0) {
            size_t cap = 0;
            uint8_t* buf = AMediaCodec_getOutputBuffer(codec_, size_t(out), &cap);
            if (buf && info.size > 0) append(buf + info.offset, size_t(info.size));
            AMediaCodec_releaseOutputBuffer(codec_, size_t(out), false);
            if (info.flags & AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM) outputEnded_ = true;
        } else if (out == AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED) {
            AMediaFormat* f = AMediaCodec_getOutputFormat(codec_);
            int32_t sr = 0, ch = 0, enc = kEncodingPcm16;
            if (AMediaFormat_getInt32(f, AMEDIAFORMAT_KEY_SAMPLE_RATE, &sr) && sr > 0) rate_ = sr;
            if (AMediaFormat_getInt32(f, AMEDIAFORMAT_KEY_CHANNEL_COUNT, &ch) && ch > 0) channels_ = ch;
            if (AMediaFormat_getInt32(f, "pcm-encoding", &enc)) encoding_ = enc;
            AMediaFormat_delete(f);
            if (format_.sampleRate > 0 && rate_ != format_.sampleRate) {
                // A mid-stream rate change would put the cache on two clocks.
                SLOGW("decoder changed rate mid-stream (%d -> %d)", format_.sampleRate, rate_);
                return false;
            }
        } else if (out != AMEDIACODEC_INFO_TRY_AGAIN_LATER &&
                   out != AMEDIACODEC_INFO_OUTPUT_BUFFERS_CHANGED) {
            return false;
        }
        return true;
    }

    // Converts decoder output to interleaved int16 stereo.
    void append(const uint8_t* data, size_t bytes) {
        const int ch = channels_;
        if (encoding_ == kEncodingPcmFloat) {
            const size_t frames = bytes / (sizeof(float) * size_t(ch));
            const float* s = reinterpret_cast<const float*>(data);
            for (size_t i = 0; i < frames; ++i) {
                const float l = s[i * ch], r = ch > 1 ? s[i * ch + 1] : l;
                pending_.push_back(toI16(l));
                pending_.push_back(toI16(r));
            }
        } else {
            const size_t frames = bytes / (sizeof(int16_t) * size_t(ch));
            const int16_t* s = reinterpret_cast<const int16_t*>(data);
            for (size_t i = 0; i < frames; ++i) {
                const int16_t l = s[i * ch];
                pending_.push_back(l);
                pending_.push_back(ch > 1 ? s[i * ch + 1] : l);
            }
        }
    }

    static int16_t toI16(float x) {
        const float s = x * 32768.0f;
        if (s >= 32767.0f) return 32767;
        if (s <= -32768.0f) return -32768;
        return int16_t(s);
    }

    std::string path_;
    int fd_;
    AMediaExtractor* extractor_ = nullptr;
    AMediaCodec* codec_ = nullptr;
    int rate_ = 0;
    int channels_ = 2;
    int encoding_ = kEncodingPcm16;
    bool inputEnded_ = false;
    bool outputEnded_ = false;
    std::vector<int16_t> pending_;  // decoded, not yet read: [head_, size())
    size_t head_ = 0;
    PcmFormat format_;
};

}  // namespace

std::unique_ptr<PcmSource> createNdkPcmSource(const std::string& path, int fd) {
    return std::make_unique<NdkPcmSource>(path, fd);
}

}  // namespace stems
}  // namespace hype
