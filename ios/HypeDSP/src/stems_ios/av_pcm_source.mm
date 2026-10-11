#include "av_pcm_source.h"

#import <AVFoundation/AVFoundation.h>

#include <algorithm>
#include <cstring>
#include <vector>

namespace hype {
namespace stems {
namespace {

class AvPcmSource final : public PcmSource {
public:
    explicit AvPcmSource(std::string url) : url_(std::move(url)) {}

    ~AvPcmSource() override {
        @autoreleasepool {
            [reader_ cancelReading];
            reader_ = nil;
            output_ = nil;
        }
    }

    bool open(std::string* reason) override {
        @autoreleasepool {
            NSURL* url = [NSURL URLWithString:[NSString stringWithUTF8String:url_.c_str()]];
            if (!url) {
                *reason = "unsupported";
                return false;
            }
            // YouTube's audio downloads are MP4 with the "dash" brand. A
            // backstop for the app's exclusion list: its policy forbids
            // separating them.
            if (url.isFileURL) {
                NSFileHandle* fh = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
                NSData* head = [fh readDataOfLength:12];
                [fh closeFile];
                if (head.length == 12 && std::memcmp(static_cast<const char*>(head.bytes) + 4, "ftypdash", 8) == 0) {
                    *reason = "youtube";
                    return false;
                }
            }
            AVURLAsset* asset = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey : @YES}];
            if (asset.hasProtectedContent) {
                *reason = "protected";
                return false;
            }
            AVAssetTrack* track = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
            if (!track) {
                *reason = "unsupported";
                return false;
            }
            // The asset's own rate: no resampling here, the engine does it.
            int rate = 0;
            for (id desc in track.formatDescriptions) {
                const AudioStreamBasicDescription* asbd =
                    CMAudioFormatDescriptionGetStreamBasicDescription((__bridge CMAudioFormatDescriptionRef)desc);
                if (asbd && asbd->mSampleRate > 0) {
                    rate = int(asbd->mSampleRate);
                    break;
                }
            }
            if (rate <= 0) {
                *reason = "unsupported";
                return false;
            }
            NSError* error = nil;
            reader_ = [AVAssetReader assetReaderWithAsset:asset error:&error];
            if (!reader_) {
                *reason = "decode";
                return false;
            }
            NSDictionary* settings = @{
                AVFormatIDKey : @(kAudioFormatLinearPCM),
                AVLinearPCMBitDepthKey : @16,
                AVLinearPCMIsFloatKey : @NO,
                AVLinearPCMIsBigEndianKey : @NO,
                AVLinearPCMIsNonInterleaved : @NO,
                AVNumberOfChannelsKey : @2,  // down/up-mix to stereo
                AVSampleRateKey : @(rate),
            };
            output_ = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:settings];
            output_.alwaysCopiesSampleData = NO;
            if (![reader_ canAddOutput:output_]) {
                *reason = "unsupported";
                return false;
            }
            [reader_ addOutput:output_];
            if (![reader_ startReading]) {
                *reason = reader_.error.code == AVErrorContentIsProtected ? "protected" : "decode";
                return false;
            }
            format_.sampleRate = rate;
            const double secs = CMTimeGetSeconds(asset.duration);
            format_.durationFrames = secs > 0 ? int64_t(secs * rate) : -1;
            return true;
        }
    }

    PcmFormat format() const override { return format_; }

    int read(int16_t* dst, int maxFrames) override {
        @autoreleasepool {
            while (available() < size_t(maxFrames) * 2 && !ended_) {
                CMSampleBufferRef sb = [output_ copyNextSampleBuffer];
                if (!sb) {
                    if (reader_.status == AVAssetReaderStatusFailed) return -1;
                    ended_ = true;
                    break;
                }
                CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sb);
                const size_t len = block ? CMBlockBufferGetDataLength(block) : 0;
                if (len > 0) {
                    const size_t old = pending_.size();
                    pending_.resize(old + len / sizeof(int16_t));
                    CMBlockBufferCopyDataBytes(block, 0, len, pending_.data() + old);
                }
                CFRelease(sb);
            }
            const int frames = int(std::min(available() / 2, size_t(maxFrames)));
            std::memcpy(dst, pending_.data() + head_, size_t(frames) * 2 * sizeof(int16_t));
            head_ += size_t(frames) * 2;
            if (head_ > (1u << 16) && head_ * 2 > pending_.size()) {
                pending_.erase(pending_.begin(), pending_.begin() + long(head_));
                head_ = 0;
            }
            return frames;
        }
    }

private:
    size_t available() const { return pending_.size() - head_; }

    std::string url_;
    AVAssetReader* reader_ = nil;
    AVAssetReaderTrackOutput* output_ = nil;
    PcmFormat format_;
    std::vector<int16_t> pending_;
    size_t head_ = 0;
    bool ended_ = false;
};

}  // namespace

std::unique_ptr<PcmSource> createAvPcmSource(const std::string& url) {
    return std::make_unique<AvPcmSource>(url);
}

}  // namespace stems
}  // namespace hype
