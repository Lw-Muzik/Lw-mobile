#include "stft.h"

#include <cmath>

namespace hype {
namespace stems {

StereoStft::StereoStft() : fft_(kNfft), window_(kNfft), re_(kNfft), im_(kNfft) {
    // PERIODIC Hann (N+1-point symmetric window without its last sample). The
    // symmetric one differs by one sample and no longer matches training.
    for (int n = 0; n < kNfft; ++n) {
        window_[n] = float(0.5 - 0.5 * std::cos(2.0 * M_PI * double(n) / double(kNfft)));
    }
}

void StereoStft::forward(const float* l, const float* r,
                         float* lRe, float* lIm, float* rRe, float* rIm) {
    for (int n = 0; n < kNfft; ++n) {
        re_[n] = l[n] * window_[n];
        im_[n] = r[n] * window_[n];
    }
    fft_.transform(re_.data(), im_.data(), /*inverse=*/false);
    // Z = FFT(l + i r)  =>  L[k] = (Z[k] + conj Z[N-k]) / 2,
    //                       R[k] = (Z[k] - conj Z[N-k]) / 2i.
    for (int k = 0; k < kSpecBins; ++k) {
        const int m = (k == 0) ? 0 : kNfft - k;
        const float zr = re_[k], zi = im_[k];
        const float wr = re_[m], wi = im_[m];
        lRe[k] = 0.5f * (zr + wr);
        lIm[k] = 0.5f * (zi - wi);
        rRe[k] = 0.5f * (zi + wi);
        rIm[k] = -0.5f * (zr - wr);
    }
}

void StereoStft::inverse(const float* lRe, const float* lIm, const float* rRe, const float* rIm,
                         float* outL, float* outR) {
    // Y = L + i R over the full circle, using L[N-k] = conj L[k] (same for R).
    for (int k = 0; k < kSpecBins; ++k) {
        re_[k] = lRe[k] - rIm[k];
        im_[k] = lIm[k] + rRe[k];
    }
    for (int k = kSpecBins; k < kNfft; ++k) {
        const int m = kNfft - k;
        re_[k] = lRe[m] + rIm[m];
        im_[k] = -lIm[m] + rRe[m];
    }
    fft_.transform(re_.data(), im_.data(), /*inverse=*/true);
    const float scale = 1.0f / float(kNfft);
    for (int n = 0; n < kNfft; ++n) {
        outL[n] = re_[n] * scale * window_[n];
        outR[n] = im_[n] * scale * window_[n];
    }
}

}  // namespace stems
}  // namespace hype
