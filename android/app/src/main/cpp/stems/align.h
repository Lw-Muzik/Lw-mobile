#pragma once
// Finds the sample offset between what the player outputs and the engine's
// own decode of the same file.
//
// They come from two decoders that should agree on every sample but not on
// where sample 0 is: encoder-delay trimming, VBR seek tables and priming all
// shift the start by up to a few thousand samples. Normalised cross-correlation
// of a short capture of the live audio against the decode recovers the exact
// integer offset, so switching between the original and the stems is
// seamless.

namespace hype {
namespace stems {

// `captured` has n mono samples taken from the live stream at player position
// p. `reference` has n + 2*maxLag mono samples of the decode starting at
// p - maxLag. On success *lag is the offset L in [-maxLag, maxLag] with
// captured[i] ~ decode[p + i + L], and *score its normalised correlation.
bool findLag(const float* captured, int n, const float* reference, int maxLag,
             int* lag, float* score);

}  // namespace stems
}  // namespace hype
