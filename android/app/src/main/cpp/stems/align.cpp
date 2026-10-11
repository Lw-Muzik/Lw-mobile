#include "align.h"
#include "fft.h"

#include <cmath>
#include <vector>

namespace hype {
namespace stems {

bool findLag(const float* captured, int n, const float* reference, int maxLag,
             int* lag, float* score) {
    const int refLen = n + 2 * maxLag;
    int m = 1;
    while (m < refLen) m <<= 1;

    // corr[k] = sum_i captured[i] * reference[i + k] for k in [0, 2*maxLag],
    // via IFFT(conj(FFT(captured)) * FFT(reference)). No wrap-around: i + k
    // never reaches refLen <= m.
    std::vector<float> ar(m, 0.0f), ai(m, 0.0f), br(m, 0.0f), bi(m, 0.0f);
    double capEnergy = 0.0;
    for (int i = 0; i < n; ++i) {
        ar[i] = captured[i];
        capEnergy += double(captured[i]) * captured[i];
    }
    for (int i = 0; i < refLen; ++i) br[i] = reference[i];
    if (capEnergy < 1e-6) return false;  // silence carries no timing

    Fft fft(m);
    fft.transform(ar.data(), ai.data(), false);
    fft.transform(br.data(), bi.data(), false);
    for (int k = 0; k < m; ++k) {
        // conj(A) * B
        const float r = ar[k] * br[k] + ai[k] * bi[k];
        const float im = ar[k] * bi[k] - ai[k] * br[k];
        ar[k] = r;
        ai[k] = im;
    }
    fft.transform(ar.data(), ai.data(), true);

    // Energy of every n-sample window of the reference, for normalisation.
    std::vector<double> prefix(refLen + 1, 0.0);
    for (int i = 0; i < refLen; ++i) prefix[i + 1] = prefix[i] + double(reference[i]) * reference[i];

    int best = -1;
    double bestScore = -2.0;
    for (int k = 0; k <= 2 * maxLag; ++k) {
        const double e = prefix[k + n] - prefix[k];
        if (e < 1e-9) continue;
        const double c = double(ar[k]) / double(m);
        const double s = c / std::sqrt(capEnergy * e);
        if (s > bestScore) { bestScore = s; best = k; }
    }
    if (best < 0) return false;
    *lag = best - maxLag;
    *score = float(bestScore);
    return true;
}

}  // namespace stems
}  // namespace hype
