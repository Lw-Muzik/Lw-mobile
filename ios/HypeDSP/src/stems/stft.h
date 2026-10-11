#pragma once
// Stereo STFT frames for Spleeter: periodic Hann, kNfft points.
//
// Both channels go through ONE complex FFT (left in the real part, right in
// the imaginary part) and are separated afterwards using Hermitian symmetry;
// the inverse does the same trick in reverse. Halves the FFT count.

#include "fft.h"
#include "stem_config.h"

#include <vector>

namespace hype {
namespace stems {

class StereoStft {
public:
    StereoStft();

    const std::vector<float>& window() const { return window_; }

    // Forward transform of one frame. `l`/`r` point at kNfft raw samples; the
    // analysis window is applied here. Outputs kSpecBins complex bins/channel.
    void forward(const float* l, const float* r,
                 float* lRe, float* lIm, float* rRe, float* rIm);

    // Inverse of two Hermitian spectra (kSpecBins bins each) back to two real
    // frames of kNfft samples, with the synthesis window applied. The caller
    // overlap-adds and divides by kOlaGain.
    void inverse(const float* lRe, const float* lIm, const float* rRe, const float* rIm,
                 float* outL, float* outR);

    // Sum of squared periodic-Hann windows at 75% overlap: constant 1.5.
    static constexpr float kOlaGain = 1.5f;

private:
    Fft fft_;
    std::vector<float> window_;
    std::vector<float> re_, im_;
};

}  // namespace stems
}  // namespace hype
