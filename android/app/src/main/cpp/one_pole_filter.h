#pragma once

// Simple one-pole lowpass filter for reverb damping.
// coeff=0: no filtering (bright), coeff=1: full filtering (dark).
class OnePoleFilter {
public:
    OnePoleFilter() : state_(0.0f), coeff_(0.0f) {}

    void setCoefficient(float coeff) { coeff_ = coeff; }

    float process(float input) {
        state_ = input + coeff_ * (state_ - input);
        return state_;
    }

    void clear() { state_ = 0.0f; }

private:
    float state_;
    float coeff_;
};
