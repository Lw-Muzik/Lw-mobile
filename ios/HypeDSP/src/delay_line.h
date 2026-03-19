#pragma once
#include <vector>
#include <cstring>
#include <cassert>
#include <cmath>

// Power-of-2 circular buffer delay line with fractional read support.
// Uses bitmask instead of modulo for zero-cost wrapping.
class DelayLine {
public:
    DelayLine() : mask_(0), writePos_(0) {}

    void resize(int maxDelaySamples) {
        // Round up to next power of 2
        int size = 1;
        while (size < maxDelaySamples + 1) size <<= 1;
        buffer_.assign(size, 0.0f);
        mask_ = size - 1;
        writePos_ = 0;
    }

    void clear() {
        std::memset(buffer_.data(), 0, buffer_.size() * sizeof(float));
        writePos_ = 0;
    }

    void write(float sample) {
        buffer_[writePos_ & mask_] = sample;
        writePos_++;
    }

    float read(int delaySamples) const {
        return buffer_[(writePos_ - delaySamples) & mask_];
    }

    // Linear interpolation for modulated delays
    float readFractional(float delaySamples) const {
        int intDelay = static_cast<int>(delaySamples);
        float frac = delaySamples - intDelay;
        float s0 = read(intDelay);
        float s1 = read(intDelay + 1);
        return s0 + frac * (s1 - s0);
    }

private:
    std::vector<float> buffer_;
    int mask_;
    int writePos_;
};
