#pragma once
// Kaiser-windowed sinc resampler for stereo blocks with absolute indexing.
//
// Stateless by design: the separator works on independent splits that can be
// computed in any order, so every call is told where its input block sits on
// the absolute timeline and computes exactly the output frames it is asked
// for. Callers supply halfWidth() frames of real input either side.

#include <cmath>
#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <utility>
#include <vector>

namespace hype {
namespace stems {

class Resampler {
public:
    explicit Resampler(int zeroCrossings = 24, int phases = 512)
        : zeroCrossings_(zeroCrossings), phases_(phases) {}

    // Input frames needed either side of an output position.
    int halfWidth(int rateIn, int rateOut) { return kernel(rateIn, rateOut).half + 1; }

    // Computes `outCount` stereo frames starting at absolute output frame
    // `outStart` (rateOut) from interleaved stereo `in`, whose first frame is
    // absolute input frame `inStart` (rateIn). Input outside the block is zero.
    void process(const float* in, int64_t inStart, int64_t inCount, int rateIn,
                 float* out, int64_t outStart, int64_t outCount, int rateOut) {
        const Kernel& k = kernel(rateIn, rateOut);
        const double ratio = double(rateIn) / double(rateOut);
        for (int64_t t = 0; t < outCount; ++t) {
            const double x = double(outStart + t) * ratio;  // absolute input position
            const int64_t i0 = int64_t(std::floor(x));
            double accL = 0.0, accR = 0.0;
            for (int64_t i = i0 - k.half + 1; i <= i0 + k.half; ++i) {
                const int64_t rel = i - inStart;
                if (rel < 0 || rel >= inCount) continue;
                const float w = k.at(float(std::fabs(x - double(i))));
                accL += double(w) * double(in[rel * 2]);
                accR += double(w) * double(in[rel * 2 + 1]);
            }
            out[t * 2] = float(accL);
            out[t * 2 + 1] = float(accR);
        }
    }

private:
    struct Kernel {
        int half = 0;          // half-width in input samples
        int phases = 0;        // table entries per input sample
        std::vector<float> table;
        float at(float dist) const {
            const float p = dist * float(phases);
            const int idx = int(p);
            if (idx + 1 >= int(table.size())) return 0.0f;
            const float frac = p - float(idx);
            return table[idx] + frac * (table[idx + 1] - table[idx]);
        }
    };

    static double besselI0(double x) {
        double sum = 1.0, term = 1.0;
        const double q = x * x / 4.0;
        for (int k = 1; k < 64; ++k) {
            term *= q / (double(k) * double(k));
            sum += term;
            if (term < 1e-12 * sum) break;
        }
        return sum;
    }

    const Kernel& kernel(int rateIn, int rateOut) {
        std::lock_guard<std::mutex> lock(mutex_);
        const auto key = std::make_pair(rateIn, rateOut);
        auto it = cache_.find(key);
        if (it != cache_.end()) return *it->second;

        // Cutoff as a fraction of the input Nyquist, a little under the lower
        // rate's Nyquist so the transition band sits outside the passband.
        const double fc = 0.97 * std::min(1.0, double(rateOut) / double(rateIn));
        auto k = std::make_unique<Kernel>();
        k->half = int(std::ceil(double(zeroCrossings_) / fc));
        k->phases = phases_;
        const double beta = 9.0;
        const double i0b = besselI0(beta);
        const int n = k->half * phases_ + 2;
        k->table.resize(n);
        for (int i = 0; i < n; ++i) {
            const double t = double(i) / double(phases_);  // distance in input samples
            if (t >= double(k->half)) { k->table[i] = 0.0f; continue; }
            const double xx = M_PI * fc * t;
            const double sinc = (t == 0.0) ? 1.0 : std::sin(xx) / xx;
            const double r = t / double(k->half);
            const double win = besselI0(beta * std::sqrt(std::max(0.0, 1.0 - r * r))) / i0b;
            k->table[i] = float(fc * sinc * win);
        }
        const Kernel& ref = *k;
        cache_[key] = std::move(k);
        return ref;
    }

    int zeroCrossings_;
    int phases_;
    std::mutex mutex_;
    std::map<std::pair<int, int>, std::unique_ptr<Kernel>> cache_;
};

}  // namespace stems
}  // namespace hype
