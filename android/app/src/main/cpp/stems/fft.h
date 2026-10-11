#pragma once
// Iterative radix-2 complex FFT on split real/imaginary arrays.
//
// Small and dependency-free on purpose: the same code runs in the Android
// library, the iOS pod and the host unit tests, so a separation computed on a
// phone can be checked bit-for-bit against the desktop.

#include <cmath>
#include <cstddef>
#include <vector>

namespace hype {
namespace stems {

class Fft {
public:
    explicit Fft(int n) : n_(n) {
        log2n_ = 0;
        while ((1 << log2n_) < n_) ++log2n_;
        rev_.resize(n_);
        for (int i = 0; i < n_; ++i) {
            int r = 0;
            for (int b = 0; b < log2n_; ++b) r |= ((i >> b) & 1) << (log2n_ - 1 - b);
            rev_[i] = r;
        }
        cos_.resize(n_ / 2);
        sin_.resize(n_ / 2);
        for (int k = 0; k < n_ / 2; ++k) {
            const double a = 2.0 * M_PI * double(k) / double(n_);
            cos_[k] = float(std::cos(a));
            sin_[k] = float(std::sin(a));
        }
    }

    int size() const { return n_; }

    // In-place transform. Forward computes X[k] = sum x[n] e^{-2*pi*i*k*n/N};
    // inverse uses e^{+...} and is NOT scaled by 1/N.
    void transform(float* re, float* im, bool inverse) const {
        for (int i = 0; i < n_; ++i) {
            const int j = rev_[i];
            if (j > i) {
                float t = re[i]; re[i] = re[j]; re[j] = t;
                t = im[i]; im[i] = im[j]; im[j] = t;
            }
        }
        const float sign = inverse ? 1.0f : -1.0f;
        for (int len = 2; len <= n_; len <<= 1) {
            const int half = len >> 1;
            const int step = n_ / len;
            for (int i = 0; i < n_; i += len) {
                for (int j = 0; j < half; ++j) {
                    const float wr = cos_[j * step];
                    const float wi = sign * sin_[j * step];
                    const int a = i + j;
                    const int b = a + half;
                    const float xr = re[b], xi = im[b];
                    const float tr = wr * xr - wi * xi;
                    const float ti = wr * xi + wi * xr;
                    re[b] = re[a] - tr;
                    im[b] = im[a] - ti;
                    re[a] += tr;
                    im[a] += ti;
                }
            }
        }
    }

private:
    int n_;
    int log2n_;
    std::vector<int> rev_;
    std::vector<float> cos_, sin_;
};

}  // namespace stems
}  // namespace hype
