#pragma once
#include <cmath>
#include <vector>
#include <algorithm>

// 3D Surround: a ring of virtual loudspeakers rendered binaurally for
// headphones (the category of Dolby Headphone / DTS Headphone:X / Windows
// Sonic). Distinct from the lightweight Crossfeed stage.
//
// ─────────────────────────────────────────────────────────────────────────────
// THIS IS A PORT. Its reference is the desktop app:
//   hypemuzik-desktop/crates/hm-dsp/src/surround3d.rs   (+ reverb.rs, delay.rs)
//
// Every constant below is that file's, to the digit. The point of the feature
// is that a track sounds the same on the phone as it does on the desktop, so a
// number changed here and not there is not a tweak — it is the two platforms
// silently diverging. If one has to move, move both.
// ─────────────────────────────────────────────────────────────────────────────
//
// Pipeline per stereo frame:
//  1. Upmix the stereo pair into virtual-speaker feeds with a Pro Logic II-style
//     passive matrix: fronts carry L/R, the rear surrounds carry a reverberated
//     mono send (pre-delayed for envelopment), and the LFE is a low-passed mono
//     sum.
//  2. Binaurally render each enabled speaker at its azimuth: the near
//     (ipsilateral) ear hears the feed directly; the far (contralateral) ear
//     hears it delayed by the inter-aural time difference, attenuated (ILD) and
//     head-shadow low-passed — the cues the brain localises azimuth from.
//  3. Sum all ears, add the LFE, normalise, and cross-fade against the dry
//     signal by `intensity`.

namespace hype {

// ── Shared constants (mirror of surround3d.rs) ──────────────────────────────

/// Effective head radius (m) for the spherical-head ITD model.
static constexpr float kHeadRadiusM = 0.0875f;
/// Speed of sound (m/s).
static constexpr float kSoundSpeed = 343.0f;
/// Virtual-speaker azimuths (degrees from front centre).
static constexpr float kFrontDeg = 30.0f;
static constexpr float kSideDeg = 90.0f;
static constexpr float kSurroundDeg = 135.0f;
/// Haas pre-delay on the rear feed so the surround image sits behind the head.
static constexpr float kSurroundPredelayS = 0.006f;
/// LFE / subwoofer crossover.
static constexpr float kLfeHz = 120.0f;
/// Front<->tweeter crossover: content above this goes to the side "tweeters",
/// below it to the front speakers (a 2-way split, like a real driver crossover).
static constexpr float kTweeterHz = 2000.0f;
/// "8D" rotation rate of the rear/reverb field (Hz) — one slow orbit per ~10s.
static constexpr float kRotationHz = 0.1f;
/// Rotation depth: how far the rear balance swings (0 = none, 1 = full L<->R).
static constexpr float kRotationDepth = 0.45f;
/// Level of the reverberant rear (surround) send into the wet mix.
static constexpr float kSurroundLevel = 0.85f;
/// Frames between renormalisations of the rotation oscillator.
static constexpr unsigned kRotRenormInterval = 4096;

static constexpr float kPi = 3.14159265358979323846f;

/// Local clamp. The standard-library one would do, but this header is compiled
/// by two separate toolchains and included from translation units it does not
/// control; not depending on a particular standard level here is free.
static inline float clampf(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

/// Flush near-denormal values to zero so slowly decaying one-pole states don't
/// linger in the denormal range, where some CPUs fall off a performance cliff.
static inline float flushDenormal(float x) {
    return (std::fabs(x) < 1e-18f) ? 0.0f : x;
}

// ── Room reverb (mirror of reverb.rs) ───────────────────────────────────────
//
// A compact Freeverb-style room reverb: parallel damped comb filters feeding
// series allpass diffusers, producing a decorrelated stereo field from a mono
// input. It is what turns the rear speakers into a large, enveloping room
// rather than a static widening.
//
// Note this is NOT the app's existing FdnReverb. That one is the user-facing
// "Room Reverb" effect with its own controls; this one is an internal part of
// the surround field, with the desktop's fixed tuning. Sharing them would mean
// the surround image changed whenever someone moved a reverb slider.

/// Comb delay tunings at 44.1 kHz (Freeverb's first four), scaled at build.
static constexpr int kCombTunings[4] = {1116, 1188, 1277, 1356};
/// Allpass diffuser tunings at 44.1 kHz.
static constexpr int kAllpassTunings[2] = {556, 441};
/// Right-channel delay offset (samples @44.1 kHz) for L/R decorrelation.
static constexpr int kStereoSpread = 23;
/// Comb feedback (room size). < 1 so the tail always decays. ~0.86 = large room.
static constexpr float kCombFeedback = 0.86f;
/// Damping: how fast highs die away in the tail (0 = bright, 1 = dark).
static constexpr float kDamp = 0.22f;
static constexpr float kAllpassFeedback = 0.5f;
/// Input attenuation so the summed combs don't overload the tail.
static constexpr float kReverbInputGain = 0.025f;

/// A damped feedback comb filter.
class Comb {
public:
    void resize(int len) {
        buf_.assign(std::max(1, len), 0.0f);
        idx_ = 0;
        store_ = 0.0f;
    }

    inline float process(float x) {
        const float out = buf_[idx_];
        // One-pole damping low-pass inside the feedback loop.
        store_ = flushDenormal(out * (1.0f - kDamp) + store_ * kDamp);
        buf_[idx_] = x + store_ * kCombFeedback;
        if (++idx_ == static_cast<int>(buf_.size())) idx_ = 0;
        return out;
    }

private:
    std::vector<float> buf_;
    int idx_ = 0;
    float store_ = 0.0f;
};

/// A Schroeder allpass diffuser.
class Allpass {
public:
    void resize(int len) {
        buf_.assign(std::max(1, len), 0.0f);
        idx_ = 0;
    }

    inline float process(float x) {
        const float buffed = buf_[idx_];
        const float out = -x + buffed;
        buf_[idx_] = flushDenormal(x + buffed * kAllpassFeedback);
        if (++idx_ == static_cast<int>(buf_.size())) idx_ = 0;
        return out;
    }

private:
    std::vector<float> buf_;
    int idx_ = 0;
};

/// Mono-in, decorrelated-stereo-out room reverb.
class RoomReverb {
public:
    void init(float sampleRate) {
        auto scale = [sampleRate](int n) {
            return std::max(1, static_cast<int>(
                std::lround(static_cast<float>(n) * sampleRate / 44100.0f)));
        };
        const int spread = scale(kStereoSpread);
        for (int i = 0; i < 4; ++i) {
            combL_[i].resize(scale(kCombTunings[i]));
            combR_[i].resize(scale(kCombTunings[i]) + spread);
        }
        for (int i = 0; i < 2; ++i) {
            apL_[i].resize(scale(kAllpassTunings[i]));
            apR_[i].resize(scale(kAllpassTunings[i]) + spread);
        }
    }

    /// Process one mono sample into a decorrelated (left, right) tail.
    inline void process(float x, float& outL, float& outR) {
        const float in = x * kReverbInputGain;
        float l = 0.0f;
        float r = 0.0f;
        for (auto& c : combL_) l += c.process(in);
        for (auto& c : combR_) r += c.process(in);
        for (auto& a : apL_) l = a.process(l);
        for (auto& a : apR_) r = a.process(r);
        outL = l;
        outR = r;
    }

private:
    Comb combL_[4];
    Comb combR_[4];
    Allpass apL_[2];
    Allpass apR_[2];
};

// ── Virtual speaker ─────────────────────────────────────────────────────────

/// One virtual loudspeaker: a near-ear direct path plus a far-ear path that is
/// delayed (ITD), attenuated (ILD) and head-shadow low-passed.
class VirtualSpeaker {
public:
    void init(float sampleRate, float azimuthDeg, float feedGain) {
        const float theta = std::fabs(azimuthDeg) * kPi / 180.0f;
        // Woodworth spherical-head ITD: t = (a/c)(theta + sin theta).
        const float itd = (kHeadRadiusM / kSoundSpeed) * (theta + std::sin(theta));
        delaySamples_ = std::max(1, static_cast<int>(std::lround(itd * sampleRate)));
        // Contralateral attenuation (ILD) and head-shadow cutoff both deepen as
        // the speaker swings to the side/rear.
        const float frontBias = (1.0f + std::cos(theta)) * 0.5f; // 1 front .. 0 behind
        contraGain_ = 0.30f + 0.70f * frontBias;
        const float shadowHz = 700.0f + 1300.0f * frontBias;
        shadowCoeff_ = std::exp(-2.0f * kPi * shadowHz / sampleRate);
        ipsiLeft_ = azimuthDeg < 0.0f;
        feedGain_ = feedGain;
        shadowState_ = 0.0f;
        buf_.assign(static_cast<size_t>(delaySamples_) + 1, 0.0f);
        idx_ = 0;
        enabled_ = true;
    }

    void setEnabled(bool on) { enabled_ = on; }
    bool enabled() const { return enabled_; }

    /// Per-ear contribution for feed sample `s`.
    inline void render(float s, float& outL, float& outR) {
        if (!enabled_) {
            outL = 0.0f;
            outR = 0.0f;
            return;
        }
        const float near = s * feedGain_;
        // Read the sample written `delaySamples_` ago, then write this one —
        // the same order as the reference DelayLine::process.
        const int n = static_cast<int>(buf_.size());
        const int read = (idx_ + n - delaySamples_) % n;
        const float delayed = buf_[read];
        buf_[idx_] = near;
        if (++idx_ == n) idx_ = 0;

        shadowState_ = flushDenormal(shadowState_ * shadowCoeff_ +
                                     delayed * (1.0f - shadowCoeff_));
        const float far = shadowState_ * contraGain_;
        if (ipsiLeft_) {
            outL = near;
            outR = far;
        } else {
            outL = far;
            outR = near;
        }
    }

    /// Gain this speaker contributes to the LEFT ear. Summed over speakers and
    /// inverted to normalise the field toward per-ear unity; by symmetry the
    /// right ear sums to the same value.
    float leftEarGain() const {
        return ipsiLeft_ ? feedGain_ : feedGain_ * contraGain_;
    }

private:
    bool ipsiLeft_ = false;
    bool enabled_ = true;
    float feedGain_ = 1.0f;
    std::vector<float> buf_;
    int idx_ = 0;
    int delaySamples_ = 1;
    float shadowState_ = 0.0f;
    float shadowCoeff_ = 0.0f;
    float contraGain_ = 1.0f;
};

/// Which speakers in the ring are switched on.
struct SurroundSpeakers {
    bool frontL = true;
    bool frontR = true;
    bool sideL = true;
    bool sideR = true;
    bool surroundL = true;
    bool surroundR = true;

    bool operator==(const SurroundSpeakers& o) const {
        return frontL == o.frontL && frontR == o.frontR && sideL == o.sideL &&
               sideR == o.sideR && surroundL == o.surroundL &&
               surroundR == o.surroundR;
    }
    bool operator!=(const SurroundSpeakers& o) const { return !(*this == o); }
};

// ── The stage ───────────────────────────────────────────────────────────────

/// Six virtual speakers, an LFE path, and a dry/wet mix.
class Surround3D {
public:
    void init(float sampleRate) {
        sampleRate_ = sampleRate > 0 ? sampleRate : 48000.0f;
        reconfigure();
    }

    void setEnabled(bool on) { enabled_ = on; }
    void setIntensity(float v) { intensity_ = clampf(v, 0.0f, 1.0f); }
    void setSubwoofer(float v) { subwoofer_ = clampf(v, 0.0f, 1.0f); }

    void setSpeakers(const SurroundSpeakers& s) {
        if (speakers_ != s) {
            speakers_ = s;
            applySpeakerStates();
        }
    }

    /// Whether the stage would change the signal (a fast bypass).
    bool isActive() const {
        return enabled_ && intensity_ > 0.0f &&
               (wetNorm_ > 0.0f || subwoofer_ > 0.0f || surroundOn_);
    }

    /// Process DEINTERLEAVED stereo in place.
    ///
    /// This is the shape RoomDSPEngine's chain works in — it splits once on the
    /// way in and re-interleaves once on the way out, so a stage that insisted
    /// on interleaved data would force two extra passes per buffer for nothing.
    void process(float* left, float* right, int frames) {
        if (!isActive() || left == nullptr || right == nullptr) return;
        for (int f = 0; f < frames; ++f) {
            processFrame(left[f], right[f], left[f], right[f]);
        }
    }

    /// Process interleaved audio in place. No-op for anything but stereo.
    void process(float* buffer, int frames, int channels) {
        if (channels < 2 || !isActive() || buffer == nullptr) return;
        for (int f = 0; f < frames; ++f) {
            const int base = f * channels;
            processFrame(buffer[base], buffer[base + 1],
                         buffer[base], buffer[base + 1]);
        }
    }

private:
    /// One frame, shared by both entry points so the two can never drift.
    inline void processFrame(float l, float r, float& outL, float& outR) {

        const float intensity = intensity_;
        const float dry = 1.0f - intensity;
        const float sub = subwoofer_;
        const float norm = wetNorm_;
        const float lfeA = lfeCoeff_;
        const float cx = xoverCoeff_;
        const bool sideLOn = sideL_.enabled();
        const bool sideROn = sideR_.enabled();
        const bool surroundOn = surroundOn_;
        const bool slOn = surroundL_.enabled();
        const bool srOn = surroundR_.enabled();
        {
            // 2-way crossover per channel: lows/mids -> front, highs -> tweeter
            // (one-pole complementary split, lp + hp == input). When a tweeter
            // is off its highs fall back to the front, so treble is never lost
            // just because a speaker was switched off.
            xoverLp_[0] = flushDenormal(xoverLp_[0] * cx + l * (1.0f - cx));
            xoverLp_[1] = flushDenormal(xoverLp_[1] * cx + r * (1.0f - cx));
            const float loL = xoverLp_[0];
            const float loR = xoverLp_[1];
            const float hiL = l - loL;
            const float hiR = r - loR;
            const float frontLIn = loL + (sideLOn ? 0.0f : hiL);
            const float frontRIn = loR + (sideROn ? 0.0f : hiR);

            // Direct field: front + side, binaurally summed and normalised.
            float el = 0.0f;
            float er = 0.0f;
            float a = 0.0f;
            float b = 0.0f;
            frontL_.render(frontLIn, a, b); el += a; er += b;
            frontR_.render(frontRIn, a, b); el += a; er += b;
            sideL_.render(hiL, a, b);       el += a; er += b;
            sideR_.render(hiR, a, b);       el += a; er += b;

            float wl = el * norm;
            float wr = er * norm;

            // Reverberant rear field: a diffuse room reverb fed by the mono
            // program, slowly rotated ("8D") and positioned at the rear +/-135.
            if (surroundOn) {
                const float mono = rearPredelayProcess((l + r) * 0.5f);
                float rvL = 0.0f;
                float rvR = 0.0f;
                reverb_.process(mono, rvL, rvR);

                // Quadrature-recurrence LFO: four multiplies instead of a
                // per-frame sin() call.
                const float lfo = rotSin_;
                const float s = rotSin_;
                const float c = rotCos_;
                rotSin_ = s * rotStepCos_ + c * rotStepSin_;
                rotCos_ = c * rotStepCos_ - s * rotStepSin_;
                if (--rotRenorm_ == 0) {
                    // Pull the oscillator back onto the unit circle so rounding
                    // can never grow or shrink the swing.
                    rotRenorm_ = kRotRenormInterval;
                    const float mag = std::sqrt(rotSin_ * rotSin_ + rotCos_ * rotCos_);
                    if (mag > 0.0f) {
                        const float inv = 1.0f / mag;
                        rotSin_ *= inv;
                        rotCos_ *= inv;
                    }
                }
                const float rotL = 1.0f + kRotationDepth * lfo;
                const float rotR = 1.0f - kRotationDepth * lfo;
                const float rearL = slOn ? rvL * rotL : 0.0f;
                const float rearR = srOn ? rvR * rotR : 0.0f;
                surroundL_.render(rearL, a, b);
                wl += kSurroundLevel * a;
                wr += kSurroundLevel * b;
                surroundR_.render(rearR, a, b);
                wl += kSurroundLevel * a;
                wr += kSurroundLevel * b;
            }

            // LFE: low-passed mono added equally to both ears.
            if (sub > 0.0f) {
                const float mid = (l + r) * 0.5f;
                lfeState_ = flushDenormal(lfeState_ * lfeA + mid * (1.0f - lfeA));
                const float lfe = lfeState_ * sub;
                wl += lfe;
                wr += lfe;
            }

            outL = l * dry + wl * intensity;
            outR = r * dry + wr * intensity;
        }
    }

    inline float rearPredelayProcess(float x) {
        const int n = static_cast<int>(rearBuf_.size());
        const int read = (rearIdx_ + n - rearDelaySamples_) % n;
        const float y = rearBuf_[read];
        rearBuf_[rearIdx_] = x;
        if (++rearIdx_ == n) rearIdx_ = 0;
        return y;
    }

    void reconfigure() {
        frontL_.init(sampleRate_, -kFrontDeg, 1.0f);
        frontR_.init(sampleRate_, kFrontDeg, 1.0f);
        sideL_.init(sampleRate_, -kSideDeg, 0.6f);
        sideR_.init(sampleRate_, kSideDeg, 0.6f);
        surroundL_.init(sampleRate_, -kSurroundDeg, 0.55f);
        surroundR_.init(sampleRate_, kSurroundDeg, 0.55f);

        rearDelaySamples_ =
            std::max(1, static_cast<int>(std::lround(kSurroundPredelayS * sampleRate_)));
        rearBuf_.assign(static_cast<size_t>(rearDelaySamples_) + 1, 0.0f);
        rearIdx_ = 0;

        lfeState_ = 0.0f;
        lfeCoeff_ = std::exp(-2.0f * kPi * kLfeHz / sampleRate_);
        xoverLp_[0] = xoverLp_[1] = 0.0f;
        xoverCoeff_ = std::exp(-2.0f * kPi * kTweeterHz / sampleRate_);
        reverb_.init(sampleRate_);

        // Seed the rotation oscillator at phase 0 and precompute its per-frame
        // step for this sample rate.
        const float rotInc = 2.0f * kPi * kRotationHz / sampleRate_;
        rotSin_ = 0.0f;
        rotCos_ = 1.0f;
        rotStepSin_ = std::sin(rotInc);
        rotStepCos_ = std::cos(rotInc);
        rotRenorm_ = kRotRenormInterval;

        applySpeakerStates();
    }

    /// Push the on/off flags into the speakers and recompute `wetNorm_`.
    void applySpeakerStates() {
        frontL_.setEnabled(speakers_.frontL);
        frontR_.setEnabled(speakers_.frontR);
        sideL_.setEnabled(speakers_.sideL);
        sideR_.setEnabled(speakers_.sideR);
        surroundL_.setEnabled(speakers_.surroundL);
        surroundR_.setEnabled(speakers_.surroundR);
        surroundOn_ = speakers_.surroundL || speakers_.surroundR;

        // Normalise the DIRECT field (front + side) toward per-ear unity. The
        // reverberant rear send is mixed separately at kSurroundLevel, so it is
        // deliberately excluded here — normalising it away is what made the
        // rear field inaudible in an earlier revision of the reference.
        float earGain = 0.0f;
        if (frontL_.enabled()) earGain += frontL_.leftEarGain();
        if (frontR_.enabled()) earGain += frontR_.leftEarGain();
        if (sideL_.enabled()) earGain += sideL_.leftEarGain();
        if (sideR_.enabled()) earGain += sideR_.leftEarGain();
        wetNorm_ = (earGain > 1e-6f) ? (1.0f / earGain) : 0.0f;
    }

    float sampleRate_ = 48000.0f;
    bool enabled_ = false;
    float intensity_ = 0.0f;
    float subwoofer_ = 0.0f;
    SurroundSpeakers speakers_{};

    VirtualSpeaker frontL_, frontR_, sideL_, sideR_, surroundL_, surroundR_;

    std::vector<float> rearBuf_;
    int rearIdx_ = 0;
    int rearDelaySamples_ = 1;

    float lfeState_ = 0.0f;
    float lfeCoeff_ = 0.0f;
    float xoverLp_[2] = {0.0f, 0.0f};
    float xoverCoeff_ = 0.0f;

    RoomReverb reverb_;

    float rotSin_ = 0.0f;
    float rotCos_ = 1.0f;
    float rotStepSin_ = 0.0f;
    float rotStepCos_ = 1.0f;
    unsigned rotRenorm_ = kRotRenormInterval;

    bool surroundOn_ = true;
    float wetNorm_ = 1.0f;
};

} // namespace hype
