// Host unit tests for the live stem engine (android/app/src/main/cpp/stems).
// Build and run: native_tests/stems/run.sh  (needs an ONNX Runtime release in ORT_DIR)
//
// Optional real-model check: set STEMS_MODEL_DIR (the four .onnx files) and
// STEMS_REF_DIR (input.wav + vocals.wav + drums.wav from reference.py).

#include "align.h"
#include "fft.h"
#include "resampler.h"
#include "separator.h"
#include "stem_config.h"
#include "stem_engine.h"
#include "stem_store.h"
#include "stem_tap.h"
#include "stft.h"
#include "test_sources.h"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <random>
#include <string>
#include <thread>
#include <vector>

using namespace hype::stems;

// ---- Tiny test framework -------------------------------------------------------

static int gFailures = 0;
static int gChecks = 0;
#define CHECK(cond)                                                                    \
    do {                                                                               \
        ++gChecks;                                                                     \
        if (!(cond)) {                                                                 \
            ++gFailures;                                                               \
            std::printf("    FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond);            \
        }                                                                              \
    } while (0)
#define CHECK_NEAR(a, b, tol)                                                          \
    do {                                                                               \
        ++gChecks;                                                                     \
        const double _a = (a), _b = (b);                                               \
        if (!(std::fabs(_a - _b) <= (tol))) {                                          \
            ++gFailures;                                                               \
            std::printf("    FAIL %s:%d  %s=%g vs %s=%g (tol %g)\n", __FILE__, __LINE__, \
                        #a, _a, #b, _b, double(tol));                                  \
        }                                                                              \
    } while (0)

struct TestCase {
    const char* name;
    std::function<void()> fn;
};
static std::vector<TestCase>& tests() {
    static std::vector<TestCase> t;
    return t;
}
struct Register {
    Register(const char* n, std::function<void()> f) { tests().push_back({n, std::move(f)}); }
};
#define TEST(name)                                     \
    static void name();                                \
    static Register reg_##name(#name, name);           \
    static void name()

// ---- Helpers ---------------------------------------------------------------------

static double snrDb(const float* ref, const float* got, size_t n) {
    double es = 0, en = 0;
    for (size_t i = 0; i < n; ++i) {
        es += double(ref[i]) * ref[i];
        const double d = double(got[i]) - ref[i];
        en += d * d;
    }
    if (en <= 0) return 300.0;
    return 10.0 * std::log10(es / en);
}

// Non-periodic test music: low "vocal" tones and high "drum" tones, each with
// a random amplitude envelope so alignment has a unique answer.
struct Synth {
    std::vector<float> low, high, mix;  // interleaved stereo
};
static Synth makeSynth(int rate, double seconds, uint32_t seed) {
    const size_t frames = size_t(rate * seconds);
    Synth s;
    s.low.assign(frames * 2, 0.0f);
    s.high.assign(frames * 2, 0.0f);
    s.mix.assign(frames * 2, 0.0f);
    std::mt19937 rng(seed);
    std::uniform_real_distribution<float> u(0.2f, 1.0f);
    // Seed-dependent pitches: two "songs" must not correlate with each other.
    // (Highs stay under 11 kHz: above it Spleeter has no net output and masks
    // are the per-frame average by design.)
    const double lowDetune = 1.0 + 0.11 * double(seed % 7);
    const double highDetune = 1.0 + 0.03 * double(seed % 7);
    const double lowF[3] = {220.0 * lowDetune, 330.0 * lowDetune, 440.0 * lowDetune};
    const double highF[3] = {6000.0 * highDetune, 7300.0 * highDetune, 8900.0 * highDetune};
    float envL = 0.5f, envH = 0.5f, tgtL = 0.5f, tgtH = 0.5f;
    for (size_t i = 0; i < frames; ++i) {
        if (i % 2205 == 0) { tgtL = u(rng); tgtH = u(rng); }
        envL += 0.001f * (tgtL - envL);
        envH += 0.001f * (tgtH - envH);
        const double t = double(i) / rate;
        double lo = 0, hi = 0;
        for (int k = 0; k < 3; ++k) {
            lo += std::sin(2 * M_PI * lowF[k] * t + k);
            hi += std::sin(2 * M_PI * highF[k] * t + 2 * k);
        }
        const float l = float(0.1 * lo) * envL;
        const float h = float(0.1 * hi) * envH;
        for (int c = 0; c < 2; ++c) {
            const float pan = c == 0 ? 1.0f : 0.8f;
            s.low[i * 2 + c] = l * pan;
            s.high[i * 2 + c] = h * (1.8f - pan);
            s.mix[i * 2 + c] = s.low[i * 2 + c] + s.high[i * 2 + c];
        }
    }
    return s;
}

// A stand-in model: "vocals" own everything under bin 200 (~2.15 kHz), "drums"
// own bins 200..1023, bass and other nothing.
class FakeSeparator : public Separator {
public:
    bool load(const std::string&, std::string*) override { return true; }
    bool isLoaded() const override { return true; }
    void unload() override {}
    bool run(int net, const float* mag, float* out, std::string*) override {
        for (int ch = 0; ch < 2; ++ch)
            for (int f = 0; f < kSplitFrames; ++f)
                for (int k = 0; k < kNetBins; ++k) {
                    const size_t i = (size_t(ch) * kSplitFrames + f) * kNetBins + k;
                    float g = 0.0f;
                    if (net == kNetVocals) g = k < 200 ? 1.0f : 0.0f;
                    if (net == kNetDrums) g = k >= 200 ? 1.0f : 0.0f;
                    out[i] = mag[i] * g;
                }
        ++runs;
        return true;
    }
    int runs = 0;
};

static std::string tmpDir() {
    const char* t = std::getenv("TMPDIR");
    return t ? std::string(t) : std::string("/tmp");
}

// ---- Tests -------------------------------------------------------------------------

TEST(fft_round_trip) {
    Fft fft(4096);
    std::mt19937 rng(1);
    std::normal_distribution<float> g;
    std::vector<float> re(4096), im(4096), r0(4096), i0(4096);
    for (int i = 0; i < 4096; ++i) { re[i] = r0[i] = g(rng); im[i] = i0[i] = g(rng); }
    fft.transform(re.data(), im.data(), false);
    fft.transform(re.data(), im.data(), true);
    double err = 0;
    for (int i = 0; i < 4096; ++i) {
        err = std::max(err, std::fabs(re[i] / 4096.0 - r0[i]));
        err = std::max(err, std::fabs(im[i] / 4096.0 - i0[i]));
    }
    CHECK(err < 1e-4);
}

TEST(stft_perfect_reconstruction) {
    // Overlap-add of windowed frames reproduces the signal exactly wherever 4
    // frames overlap — the property the stems' exact sum rests on.
    StereoStft stft;
    const int frames = 40;
    const int len = (frames - 1) * kHop + kNfft;
    std::mt19937 rng(2);
    std::normal_distribution<float> g(0.0f, 0.3f);
    std::vector<float> l(len), r(len), outL(len, 0.0f), outR(len, 0.0f);
    for (int i = 0; i < len; ++i) { l[i] = g(rng); r[i] = g(rng); }
    std::vector<float> spec(4 * kSpecBins), fl(kNfft), fr(kNfft);
    for (int f = 0; f < frames; ++f) {
        float* a = spec.data();
        stft.forward(&l[f * kHop], &r[f * kHop], a, a + kSpecBins, a + 2 * kSpecBins, a + 3 * kSpecBins);
        stft.inverse(a, a + kSpecBins, a + 2 * kSpecBins, a + 3 * kSpecBins, fl.data(), fr.data());
        for (int n = 0; n < kNfft; ++n) {
            outL[f * kHop + n] += fl[n] / StereoStft::kOlaGain;
            outR[f * kHop + n] += fr[n] / StereoStft::kOlaGain;
        }
    }
    const int a = kPad, b = (frames - 1) * kHop + kHop;  // fully overlapped region
    CHECK(snrDb(&l[a], &outL[a], size_t(b - a)) > 90.0);
    CHECK(snrDb(&r[a], &outR[a], size_t(b - a)) > 90.0);
}

TEST(stft_channels_are_independent) {
    // Packing L and R into one complex FFT must not leak one into the other.
    StereoStft stft;
    std::vector<float> l(kNfft), r(kNfft, 0.0f);
    for (int i = 0; i < kNfft; ++i) l[i] = std::sin(2 * M_PI * 37.0 * i / kNfft);
    std::vector<float> spec(4 * kSpecBins);
    float* a = spec.data();
    stft.forward(l.data(), r.data(), a, a + kSpecBins, a + 2 * kSpecBins, a + 3 * kSpecBins);
    double el = 0, er = 0;
    for (int k = 0; k < kSpecBins; ++k) {
        el += a[k] * a[k] + a[kSpecBins + k] * a[kSpecBins + k];
        er += a[2 * kSpecBins + k] * a[2 * kSpecBins + k] + a[3 * kSpecBins + k] * a[3 * kSpecBins + k];
    }
    CHECK(el > 1.0);
    CHECK(er < el * 1e-10);
}

TEST(split_geometry_tiles_the_timeline) {
    // Owned ranges are contiguous and each lies inside its split's exact span
    // with kMargin to spare.
    for (int64_t c = 0; c < 50; ++c) {
        CHECK(splitOwnedEnd(c) == splitOwnedStart(c + 1));
        const int64_t exactStart = c * kStepSamples;
        const int64_t exactEnd = exactStart + kFinalSpan;
        CHECK(splitOwnedStart(c) >= exactStart + (c == 0 ? 0 : kMargin));
        CHECK(splitOwnedEnd(c) <= exactEnd - kMargin);
        CHECK(splitContaining(splitOwnedStart(c)) == c);
        CHECK(splitContaining(splitOwnedEnd(c) - 1) == c);
    }
    // ...and at another playback rate the mapped ranges still tile.
    for (int64_t c = 0; c < 50; ++c) {
        CHECK(toRate(splitOwnedEnd(c), 48000) == toRate(splitOwnedStart(c + 1), 48000));
    }
}

TEST(resampler_tracks_a_sine) {
    Resampler rs;
    const int in = 48000, out = 44100;
    const int64_t n = 48000;
    std::vector<float> x(size_t(n) * 2);
    for (int64_t i = 0; i < n; ++i) x[size_t(i) * 2] = x[size_t(i) * 2 + 1] = float(0.5 * std::sin(2 * M_PI * 1000.0 * i / in));
    const int64_t o0 = 2000, on = 30000;
    std::vector<float> y(size_t(on) * 2), ref(size_t(on) * 2);
    rs.process(x.data(), 0, n, in, y.data(), o0, on, out);
    for (int64_t t = 0; t < on; ++t) ref[size_t(t) * 2] = ref[size_t(t) * 2 + 1] = float(0.5 * std::sin(2 * M_PI * 1000.0 * (o0 + t) / out));
    CHECK(snrDb(ref.data(), y.data(), ref.size()) > 70.0);
}

TEST(resampler_round_trip) {
    Resampler rs;
    std::mt19937 rng(3);
    std::normal_distribution<float> g(0.0f, 0.2f);
    // Band-limited content (below 18 kHz survives 44.1 <-> 48 kHz).
    const int64_t n = 44100;
    std::vector<float> x(size_t(n) * 2, 0.0f);
    for (int k = 1; k < 40; ++k) {
        const double f = 400.0 * k, ph = g(rng);
        for (int64_t i = 0; i < n; ++i) x[size_t(i) * 2] += float(0.02 * std::sin(2 * M_PI * f * i / 44100 + ph));
    }
    for (int64_t i = 0; i < n; ++i) x[size_t(i) * 2 + 1] = x[size_t(i) * 2];
    const int64_t m = n * 48000 / 44100;
    std::vector<float> up(size_t(m) * 2), back(size_t(n) * 2);
    rs.process(x.data(), 0, n, 44100, up.data(), 0, m, 48000);
    rs.process(up.data(), 0, m, 48000, back.data(), 0, n, 44100);
    const size_t a = 2000 * 2, b = size_t(n - 2000) * 2;
    CHECK(snrDb(&x[a], &back[a], b - a) > 60.0);
}

TEST(align_recovers_known_lag) {
    Synth s = makeSynth(44100, 3.0, 4);
    std::vector<float> mono(s.mix.size() / 2);
    for (size_t i = 0; i < mono.size(); ++i) mono[i] = 0.5f * (s.mix[i * 2] + s.mix[i * 2 + 1]);
    const int n = StemTap::kCaptureFrames, L = StemTap::kMaxLag;
    for (int lag : {0, 1105, -529, 2112, -4000, 8000}) {
        const int64_t p = 50000;  // player position of the capture
        std::vector<float> cap(n), ref(n + 2 * L);
        for (int i = 0; i < n; ++i) cap[i] = mono[size_t(p + i + lag)];
        for (int i = 0; i < n + 2 * L; ++i) ref[i] = mono[size_t(p - L + i)];
        int got = 99999;
        float score = 0;
        CHECK(findLag(cap.data(), n, ref.data(), L, &got, &score));
        CHECK(got == lag);
        CHECK(score > 0.99f);
    }
    std::vector<float> zero(n, 0.0f), ref(n + 2 * L, 0.1f);
    int got;
    float score;
    CHECK(!findLag(zero.data(), n, ref.data(), L, &got, &score));
}

TEST(store_publish_and_read) {
    StemStore st;
    st.configure(1000);
    CHECK(!st.covers(0, 10));
    StemStore::Write w = st.beginWrite(100, 600, 0);
    for (int i = 0; i < 500 * 2; ++i) { w.mix[i] = int16_t(i); w.v[i] = int16_t(-i); w.d[i] = 7; }
    // Not readable until published.
    std::vector<float> m(2000), v(2000), d(2000);
    CHECK(st.read(100, 10, m.data(), v.data(), d.data()) == 0);
    st.endWrite(w);
    CHECK(st.covers(100, 600));
    CHECK(!st.covers(99, 600));
    CHECK(st.readyUntil(150) == 600);
    const int got = st.read(590, 50, m.data(), v.data(), d.data());
    CHECK(got == 10);
    CHECK_NEAR(m[0], double(int16_t(490 * 2)) / 32768.0, 1e-7);
    CHECK_NEAR(d[0], 7.0 / (32768.0 * StemStore::kStemScale), 1e-7);
    // A second, contiguous slot extends the run.
    StemStore::Write w2 = st.beginWrite(600, 900, 0);
    st.endWrite(w2);
    CHECK(st.readyUntil(150) == 900);
    CHECK(st.covers(100, 900));
    st.invalidate();
    CHECK(!st.covers(100, 101));
}

TEST(store_eviction_keeps_the_playhead) {
    StemStore st;
    st.configure(100);
    for (int c = 0; c < StemStore::kSlots; ++c) { auto w = st.beginWrite(c * 100, c * 100 + 100, 0); st.endWrite(w); }
    // Playhead in slot 1: writing the next range must evict slot 0, not 1..3.
    auto w = st.beginWrite(400, 500, /*keepFrom=*/100);
    st.endWrite(w);
    CHECK(!st.covers(0, 100));
    CHECK(st.covers(100, 500));
}

// Full engine path: the player's audio is the decode delayed by `lag`, the
// worker must align, separate ahead and the tap must cut the "vocals".
static void runEnginePath(int fileRate, int playRate, int lag, const char* label) {
    std::printf("    [%s]\n", label);
    Synth s = makeSynth(fileRate, 30.0, 5);
    auto fake = std::make_unique<FakeSeparator>();
    auto engine = StemEngine::createForTesting(std::move(fake));
    engine->setCacheDir(tmpDir());
    const std::vector<float> fileAudio = s.mix;
    const uint32_t id = engine->registerTrack(
        std::string("file:///tmp/test_") + label + ".wav",
        [fileAudio, fileRate] { return std::make_unique<stemtest::MemorySource>(fileAudio, fileRate); }, "");
    CHECK(id != 0);

    // What the player outputs, at the playback rate: the decode shifted by lag.
    Resampler rs;
    std::vector<float> live = s.mix, liveLow = s.low;
    if (playRate != fileRate) {
        const int64_t n = int64_t(s.mix.size() / 2);
        const int64_t m = n * playRate / fileRate;
        live.assign(size_t(m) * 2, 0.0f);
        liveLow.assign(size_t(m) * 2, 0.0f);
        rs.process(s.mix.data(), 0, n, fileRate, live.data(), 0, m, playRate);
        rs.process(s.low.data(), 0, n, fileRate, liveLow.data(), 0, m, playRate);
    }
    StemTap tap(*engine);
    tap.setSampleRate(playRate);
    tap.setKeys(id, 0);
    tap.onFlush();
    tap.onBufferTime(int64_t(std::max(0, -lag)) * 1000000 / playRate);
    engine->setArmed(true);
    engine->setLevels(0.0f, 1.0f, 1.0f);  // vocals off

    const int block = 1024;
    const int64_t total = int64_t(live.size() / 2) - lag - 1;
    std::vector<float> buf(size_t(block) * 2);
    double eLowIn = 0, eLowOut = 0, eHighIn = 0, eErr = 0;
    bool sawReady = false;
    int64_t measured = 0;
    // Player frame p plays decode frame p + lag, so start where both exist.
    for (int64_t p = std::max(0, -lag); p + block < total; p += block) {
        for (int i = 0; i < block * 2; ++i) buf[size_t(i)] = live[size_t((p + lag) * 2 + i)];
        tap.process(buf.data(), block);
        if (engine->status().state == "ready") sawReady = true;
        // Measure only once stems are fully in (after the first 8 s).
        if (sawReady && p > int64_t(playRate) * 8) {
            for (int i = 0; i < block * 2; ++i) {
                const float lo = liveLow[size_t((p + lag) * 2 + i)];
                const float x = live[size_t((p + lag) * 2 + i)];
                const float hi = x - lo;
                const float expect = hi;  // vocals removed
                eLowIn += double(lo) * lo;
                eHighIn += double(hi) * hi;
                eErr += double(buf[size_t(i)] - expect) * double(buf[size_t(i)] - expect);
                eLowOut += 0;
            }
            measured += block;
        }
        // Run a little faster than real time but give the worker room.
        std::this_thread::sleep_for(std::chrono::microseconds(2500));
    }
    CHECK(sawReady);
    CHECK(measured > playRate * 5);
    const double removal = eHighIn > 0 ? 10.0 * std::log10(eHighIn / std::max(eErr, 1e-20)) : 0;
    std::printf("      output vs expected (vocals removed): %.1f dB SNR over %.1f s\n", removal,
                double(measured) / playRate);
    CHECK(removal > 30.0);
    (void)eLowIn;
    (void)eLowOut;
}

TEST(engine_aligns_separates_and_mixes_44k) { runEnginePath(44100, 44100, 1105, "44k_lag1105"); }
TEST(engine_handles_48k_files) { runEnginePath(48000, 48000, -700, "48k_lagm700"); }

// The fake, as slow as a phone: a split costs a real share of its 11.8 s.
class SlowFakeSeparator : public FakeSeparator {
public:
    explicit SlowFakeSeparator(int msPerNet) : ms_(msPerNet) {}
    bool run(int net, const float* mag, float* out, std::string* error) override {
        std::this_thread::sleep_for(std::chrono::milliseconds(ms_));
        return FakeSeparator::run(net, mag, out, error);
    }

private:
    int ms_;
};

TEST(engine_engages_one_job_after_a_seek_and_holds) {
    // A seek landing 2 s before a grid split ends, with ~1.7 s jobs: the grid
    // separated that split, finished after the playhead left it, then the next
    // one (stems after ~3.9 s). A split started where the playhead will be is
    // heard after one job and the original never comes back.
    const int rate = 44100;
    Synth s = makeSynth(rate, 54.0, 9);
    auto engine = StemEngine::createForTesting(std::make_unique<SlowFakeSeparator>(400));
    engine->setCacheDir(tmpDir());
    const std::vector<float> audio = s.mix;
    const uint32_t id = engine->registerTrack(
        "file:///tmp/test_seek.wav", [audio, rate] { return std::make_unique<stemtest::MemorySource>(audio, rate); }, "");
    StemTap tap(*engine);
    tap.setSampleRate(rate);
    tap.setKeys(id, 0);
    engine->setArmed(true);
    engine->setLevels(0.0f, 1.0f, 1.0f);

    const int block = 1024;
    std::vector<float> buf(size_t(block) * 2);
    // Plays [from, to) in real time; returns the first frame of the first block
    // with the vocals gone (-1: never) and how many blocks after it had them.
    auto play = [&](int64_t from, int64_t to, int64_t* removedAt, int* relapses) {
        tap.onFlush();
        tap.onBufferTime(from * 1000000 / rate);
        *removedAt = -1;
        *relapses = 0;
        auto due = std::chrono::steady_clock::now();
        for (int64_t p = from; p + block <= to; p += block) {
            std::copy(audio.begin() + p * 2, audio.begin() + (p + block) * 2, buf.begin());
            tap.process(buf.data(), block);
            double eLow = 0, eErr = 0;
            for (int i = 0; i < block * 2; ++i) {
                const float lo = s.low[size_t(p * 2 + i)];
                const float err = buf[size_t(i)] - s.high[size_t(p * 2 + i)];
                eLow += double(lo) * lo;
                eErr += double(err) * err;
            }
            const bool removed = eErr < 0.01 * eLow;
            if (removed && *removedAt < 0) *removedAt = p;
            if (!removed && *removedAt >= 0) ++*relapses;
            due += std::chrono::microseconds(int64_t(block) * 1000000 / rate);
            std::this_thread::sleep_until(due);
        }
    };

    int64_t at = 0;
    int relapses = 0;
    // First job of a session, from the top: with no job timed yet the engine
    // assumes a slow phone and starts it a few seconds in.
    play(0, 9 * rate, &at, &relapses);
    CHECK(at >= 0);
    CHECK(relapses == 0);

    const int64_t gridEnd = splitOwnedEnd(3);         // ~47.2 s
    const int64_t seekTo = gridEnd - 2 * rate;
    play(seekTo, seekTo + int64_t(5.5 * rate), &at, &relapses);
    CHECK(at >= 0);
    const double wait = at >= 0 ? double(at - seekTo) / rate : 99.0;
    std::printf("      stems %.2f s after the seek, %d relapsed blocks\n", wait, relapses);
    CHECK(wait < 3.0);
    CHECK(relapses == 0);
}

TEST(engine_unity_levels_pass_through) {
    // With every level at 100% the tap must not touch the audio at all.
    Synth s = makeSynth(44100, 4.0, 6);
    auto engine = StemEngine::createForTesting(std::make_unique<FakeSeparator>());
    engine->setCacheDir(tmpDir());
    const std::vector<float> audio = s.mix;
    const uint32_t id = engine->registerTrack(
        "file:///tmp/unity.wav", [audio] { return std::make_unique<stemtest::MemorySource>(audio, 44100); }, "");
    StemTap tap(*engine);
    tap.setSampleRate(44100);
    tap.setKeys(id, 0);
    tap.onFlush();
    tap.onBufferTime(0);
    engine->setArmed(true);
    std::vector<float> buf(2048);
    bool identical = true;
    for (int64_t p = 0; p + 1024 < int64_t(audio.size() / 2); p += 1024) {
        for (int i = 0; i < 2048; ++i) buf[size_t(i)] = audio[size_t(p * 2 + i)];
        tap.process(buf.data(), 1024);
        for (int i = 0; i < 2048; ++i) identical = identical && buf[size_t(i)] == audio[size_t(p * 2 + i)];
    }
    CHECK(identical);
    CHECK(!tap.active());
}

TEST(engine_reports_streams_until_given_a_copy) {
    auto engine = StemEngine::createForTesting(std::make_unique<FakeSeparator>());
    engine->setCacheDir(tmpDir());
    const std::string url = "https://rr1.googlevideo.com/videoplayback?x";
    const uint32_t a = engine->registerTrack(url, nullptr, "");
    StemTap tap(*engine);
    tap.setSampleRate(44100);
    std::vector<float> buf(2048, 0.1f);
    auto waitFor = [&](uint32_t id, const char* state) {
        tap.setKeys(id, 0);
        tap.onFlush();
        tap.onBufferTime(0);
        engine->setArmed(true);
        for (int i = 0; i < 150; ++i) {
            tap.process(buf.data(), 1024);
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
            const StemStatus st = engine->status();
            if (st.trackKey == engine->status().trackKey && st.state == state) return st;
        }
        return engine->status();
    };
    StemStatus st = waitFor(a, "unavailable");
    CHECK(st.state == "unavailable");
    CHECK(st.reason == "stream");
    // The player registers its items again on every change: still a stream.
    CHECK(engine->registerTrack(url, nullptr, "") == a);
    // A copy fetched ahead, before the player reaches the item, is kept.
    Synth s = makeSynth(44100, 6.0, 3);
    const std::vector<float> audio = s.mix;
    const std::string next = "https://rr2.googlevideo.com/videoplayback?y";
    engine->provideSource(next, [audio] { return std::make_unique<stemtest::MemorySource>(audio, 44100); });
    const uint32_t b = engine->registerTrack(next, nullptr, "");
    st = waitFor(b, "preparing");
    CHECK(st.trackKey == next);
    CHECK(st.state != "unavailable");
}

TEST(engine_separates_a_stream_once_given_its_copy) {
    // YouTube Music plays from the network; the app downloads the same file
    // while stems are in use and hands it over mid-song.
    Synth s = makeSynth(44100, 24.0, 9);
    auto engine = StemEngine::createForTesting(std::make_unique<FakeSeparator>());
    engine->setCacheDir(tmpDir());
    const std::vector<float> audio = s.mix;
    const std::string url = "https://rr3.googlevideo.com/videoplayback?id=1";
    const uint32_t id = engine->registerTrack(url, nullptr, "");
    StemTap tap(*engine);
    tap.setSampleRate(44100);
    tap.setKeys(id, 0);
    tap.onFlush();
    tap.onBufferTime(0);
    engine->setArmed(true);
    engine->setLevels(0.0f, 1.0f, 1.0f);
    std::vector<float> buf(2048);
    int64_t p = 0;
    double eHigh = 0, eErr = 0;
    auto playBlock = [&](bool measure) {
        for (int i = 0; i < 2048; ++i) buf[size_t(i)] = audio[size_t(p * 2 + i)];
        tap.process(buf.data(), 1024);
        if (measure) {
            for (int i = 0; i < 2048; ++i) {
                const float hi = s.high[size_t(p * 2 + i)];
                eHigh += double(hi) * hi;
                eErr += double(buf[size_t(i)] - hi) * double(buf[size_t(i)] - hi);
            }
        }
        p += 1024;
        std::this_thread::sleep_for(std::chrono::microseconds(2500));
    };
    for (int k = 0; k < 40; ++k) playBlock(false);  // ~1 s of the stream as is
    CHECK(engine->status().state == "unavailable");
    CHECK(engine->status().reason == "stream");
    CHECK(!tap.active());

    engine->provideSource(url, [audio] { return std::make_unique<stemtest::MemorySource>(audio, 44100); });
    bool ready = false;
    for (int k = 0; k < 400 && !ready; ++k) {
        playBlock(false);
        ready = engine->status().state == "ready" && tap.active();
    }
    CHECK(ready);
    for (int k = 0; k < 8; ++k) playBlock(false);  // past the fade in
    for (int k = 0; k < 40; ++k) playBlock(true);
    const double snr = eHigh > 0 && eErr > 0 ? 10.0 * std::log10(eHigh / eErr) : 0.0;
    std::printf("      vocals removed from the stream: %.1f dB SNR\n", snr);
    CHECK(snr > 30.0);
}

TEST(tap_follows_gapless_and_seek_transitions) {
    auto engine = StemEngine::createForTesting(std::make_unique<FakeSeparator>());
    StemTap tap(*engine);
    tap.setSampleRate(44100);
    std::vector<float> buf(2048, 0.0f);
    // Playing A with B queued.
    tap.setKeys(1, 2);
    tap.onFlush();
    tap.onBufferTime(0);
    tap.process(buf.data(), 1024);
    CHECK(tap.view().track == 1);
    // Gapless transition: the renderer moves on before the app knows.
    tap.onStreamChange();
    tap.onBufferTime(0);
    tap.process(buf.data(), 1024);
    CHECK(tap.view().track == 2);
    CHECK(tap.view().pos == 1024);
    // The app catches up (B current, C next): no change.
    tap.setKeys(2, 3);
    tap.process(buf.data(), 1024);
    CHECK(tap.view().track == 2);
    // The user jumps to item 7: the app updates keys, then the player flushes.
    tap.setKeys(7, 8);
    tap.onFlush();
    tap.onStreamChange();
    tap.onBufferTime(5000000);
    tap.process(buf.data(), 1024);
    CHECK(tap.view().track == 7);
    CHECK(tap.view().pos == 5 * 44100 + 1024);
    // A seek inside 7 keeps the track.
    tap.onFlush();
    tap.onBufferTime(1000000);
    tap.process(buf.data(), 1024);
    CHECK(tap.view().track == 7);
    // A gapless boundary where the sink reconfigures (stream change, THEN a
    // flush) is still a move to the next item, not a seek.
    tap.setKeys(7, 11);
    tap.onStreamChange();
    tap.onFlush();
    tap.onBufferTime(0);
    tap.process(buf.data(), 1024);
    CHECK(tap.view().track == 11);
    // A load where the app's keys arrive after the first buffer.
    tap.onFlush();
    tap.onStreamChange();
    tap.onBufferTime(0);
    tap.setKeys(9, 0);
    tap.process(buf.data(), 1024);
    CHECK(tap.view().track == 9);
}

TEST(engine_corrects_a_wrong_track_guess) {
    // The tap starts on the wrong track (as after a gapless move it misread);
    // alignment cannot match, so after two misses it switches to the other
    // item the player named, aligns, and stems engage.
    Synth right = makeSynth(44100, 20.0, 7);
    Synth wrong = makeSynth(44100, 20.0, 8);
    auto engine = StemEngine::createForTesting(std::make_unique<FakeSeparator>());
    engine->setCacheDir(tmpDir());
    const std::vector<float> ra = right.mix, wa = wrong.mix;
    const uint32_t idRight = engine->registerTrack(
        "file:///tmp/right.wav", [ra] { return std::make_unique<stemtest::MemorySource>(ra, 44100); }, "");
    const uint32_t idWrong = engine->registerTrack(
        "file:///tmp/wrong.wav", [wa] { return std::make_unique<stemtest::MemorySource>(wa, 44100); }, "");
    StemTap tap(*engine);
    tap.setSampleRate(44100);
    tap.setKeys(idWrong, idRight);  // the player is really playing `right`
    tap.onFlush();
    tap.onBufferTime(0);
    engine->setArmed(true);
    engine->setLevels(0.0f, 1.0f, 1.0f);
    std::vector<float> buf(2048);
    bool switched = false, ready = false;
    for (int64_t p = 0; p + 1024 < int64_t(ra.size() / 2) && !ready; p += 1024) {
        for (int i = 0; i < 2048; ++i) buf[size_t(i)] = ra[size_t(p * 2 + i)];
        tap.process(buf.data(), 1024);
        switched = switched || tap.view().track == idRight;
        ready = engine->status().state == "ready" && tap.view().track == idRight;
        std::this_thread::sleep_for(std::chrono::microseconds(2500));
    }
    CHECK(switched);
    CHECK(ready);
}

TEST(real_spleeter_matches_python_reference) {
    const char* modelDir = std::getenv("STEMS_MODEL_DIR");
    const char* refDir = std::getenv("STEMS_REF_DIR");
    if (!modelDir || !refDir) {
        std::printf("    (skipped: set STEMS_MODEL_DIR and STEMS_REF_DIR)\n");
        return;
    }
    std::vector<float> in, refV, refD;
    int rate = 0, r2 = 0, r3 = 0;
    CHECK(stemtest::readWav(std::string(refDir) + "/input.wav", &in, &rate));
    CHECK(stemtest::readWav(std::string(refDir) + "/vocals.wav", &refV, &r2));
    CHECK(stemtest::readWav(std::string(refDir) + "/drums.wav", &refD, &r3));
    CHECK(rate == 44100);
    auto engine = StemEngine::createForTesting(nullptr);
    std::string err;
    const auto t0 = std::chrono::steady_clock::now();
    CHECK(engine->loadModel(modelDir, &err));
    std::printf("    model load %.2f s %s\n",
                std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count(), err.c_str());
    const StemEngine::Benchmark b = engine->benchmark();
    std::printf("    benchmark: ok=%d rtf=%.3f (%d ms per 11.8 s split) %s\n", b.ok, b.rtf, b.millis, b.error.c_str());
    CHECK(b.ok);

    // Split 0's input span: [-kPad, kInputSpan - kPad).
    std::vector<float> span(size_t(kInputSpan) * 2, 0.0f);
    for (int64_t i = 0; i < kInputSpan; ++i) {
        const int64_t src = i - kPad;
        if (src >= 0 && src < int64_t(in.size() / 2)) {
            span[size_t(i) * 2] = in[size_t(src) * 2];
            span[size_t(i) * 2 + 1] = in[size_t(src) * 2 + 1];
        }
    }
    std::vector<float> v, d;
    CHECK(engine->separateForTesting(span.data(), &v, &d, &err));
    // Split 0 owns [0, splitOwnedEnd(0)); the reference's first 512-frame
    // split covers exactly the same frames there.
    const int64_t n = std::min<int64_t>(splitOwnedEnd(0), int64_t(refV.size() / 2));
    std::vector<float> gotV(size_t(n) * 2), gotD(size_t(n) * 2);
    for (int64_t i = 0; i < n * 2; ++i) {
        gotV[size_t(i)] = v[size_t(kPad * 2 + i)];
        gotD[size_t(i)] = d[size_t(kPad * 2 + i)];
    }
    const double sv = snrDb(refV.data(), gotV.data(), size_t(n) * 2);
    const double sd = snrDb(refD.data(), gotD.data(), size_t(n) * 2);
    std::printf("    C++ vs Python reference over %.1f s: vocals %.1f dB, drums %.1f dB\n", double(n) / 44100, sv, sd);
    CHECK(sv > 40.0);
    CHECK(sd > 40.0);
}

int main(int argc, char** argv) {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    const char* only = argc > 1 ? argv[1] : nullptr;
    for (const TestCase& t : tests()) {
        if (only && std::string(t.name).find(only) == std::string::npos) continue;
        const int before = gFailures;
        const auto t0 = std::chrono::steady_clock::now();
        std::printf("%s\n", t.name);
        t.fn();
        const double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        std::printf("  %s (%.2f s)\n", gFailures == before ? "ok" : "FAILED", secs);
    }
    std::printf("\n%d checks, %d failures\n", gChecks, gFailures);
    return gFailures == 0 ? 0 : 1;
}
