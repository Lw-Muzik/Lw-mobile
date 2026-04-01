#pragma once
/**
 * fft_visualizer.h — Lock-free PCM capture + FFT for Flutter visualizer.
 *
 * Replaces Android's Visualizer API (which needs audio session ID) with a
 * custom pipeline that taps PCM directly from ExoPlayer's AudioProcessor.
 *
 * Architecture:
 *   Audio thread  →  ring buffer (SPSC, lock-free)
 *   Viz thread    →  reads ring buffer, applies Hann window, computes FFT,
 *                     maps to log-frequency bands, returns float[NUM_BANDS]
 *
 * FFT: in-place radix-2 Cooley-Tukey via the "pack two reals" trick.
 *       2048-point real FFT at 44.1kHz = 21.5 Hz resolution, 46ms window.
 */

#include <cmath>
#include <cstring>
#include <atomic>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

class FFTVisualizer {
public:
    static constexpr int FFT_SIZE   = 2048;
    static constexpr int HALF_FFT   = FFT_SIZE / 2;
    static constexpr int NUM_BANDS  = 64;

    // Configurable parameters (set from Java/Dart)
    float attackRate  = 0.6f;   // How fast bands rise (0.1 = smooth, 0.9 = snappy)
    float decayRate   = 0.15f;  // How fast bands fall (0.05 = slow, 0.5 = fast)
    float gain        = 1.0f;   // Beat sensitivity / amplitude boost (0.5 = subtle, 3.0 = intense)

    FFTVisualizer() {
        // Pre-compute Hann window coefficients
        for (int i = 0; i < FFT_SIZE; i++) {
            window_[i] = 0.5f * (1.0f - cosf(2.0f * (float)M_PI * i / (FFT_SIZE - 1)));
        }
        computeBandEdges();

        memset(ringBuf_, 0, sizeof(ringBuf_));
        memset(smoothBands_, 0, sizeof(smoothBands_));
    }

    // ── Audio thread: write PCM here ──────────────────────────────────

    /**
     * Called from audio thread (ExoPlayer AudioProcessor).
     * Downmixes stereo-interleaved float PCM to mono and writes to ring buffer.
     */
    void pushSamples(const float* stereoInterleaved, int numFrames) {
        for (int i = 0; i < numFrames; i++) {
            float mono = (stereoInterleaved[i * 2] + stereoInterleaved[i * 2 + 1]) * 0.5f;
            ringBuf_[writePos_ & RING_MASK] = mono;
            writePos_++;
        }
        samplesAvailable_.fetch_add(numFrames, std::memory_order_release);
    }

    // ── Viz thread: compute FFT + bands here (~30fps) ─────────────────

    /**
     * Computes FFT and maps to log-frequency bands.
     * Returns true if new data was computed.
     * Output: bands[0..NUM_BANDS-1] = smoothed magnitude 0.0–1.0
     */
    bool computeBands(float* bands) {
        int avail = samplesAvailable_.load(std::memory_order_acquire);
        if (avail < FFT_SIZE) return false;

        // Snap the latest FFT_SIZE samples from ring buffer + apply Hann window
        int rp = writePos_ - FFT_SIZE;
        for (int i = 0; i < FFT_SIZE; i++) {
            inputBuf_[i] = ringBuf_[(rp + i) & RING_MASK] * window_[i];
        }
        samplesAvailable_.store(0, std::memory_order_release);

        // ── Radix-2 FFT (real input via pack-two-reals trick) ──
        realFFT(inputBuf_, fftOut_, FFT_SIZE);

        // ── Magnitude spectrum ──
        magnitudes_[0] = fabsf(fftOut_[0]);          // DC
        magnitudes_[HALF_FFT] = fabsf(fftOut_[1]);   // Nyquist
        float peak = 0.0001f;
        for (int i = 1; i < HALF_FFT; i++) {
            float re = fftOut_[i * 2];
            float im = fftOut_[i * 2 + 1];
            magnitudes_[i] = sqrtf(re * re + im * im);
            if (magnitudes_[i] > peak) peak = magnitudes_[i];
        }

        // ── Map to log-frequency bands with smoothing ──
        for (int b = 0; b < NUM_BANDS; b++) {
            int lo = bandEdges_[b];
            int hi = bandEdges_[b + 1];
            float sum = 0;
            for (int i = lo; i < hi; i++) {
                sum += magnitudes_[i];
            }
            float avg = sum / std::max(1, hi - lo);
            // Normalize + perceptual compression + gain (beat sensitivity)
            float normalized = powf(avg / peak, 0.6f) * gain;
            if (normalized > 1.0f) normalized = 1.0f;

            // Asymmetric smoothing with configurable attack/decay
            if (normalized > smoothBands_[b]) {
                smoothBands_[b] += (normalized - smoothBands_[b]) * attackRate;
            } else {
                smoothBands_[b] += (normalized - smoothBands_[b]) * decayRate;
            }
            bands[b] = smoothBands_[b];
        }
        return true;
    }

    /**
     * Also produce waveform bytes (0-255, center=128) for compatibility
     * with existing Flutter visualizer painters.
     * Output: wave[0..size-1], returns actual size written.
     */
    int getWaveform(uint8_t* wave, int maxSize) {
        int count = std::min(maxSize, (int)FFT_SIZE);
        int rp = writePos_ - count;
        for (int i = 0; i < count; i++) {
            float s = ringBuf_[(rp + i) & RING_MASK];
            // Clamp [-1,1] → [0,255]
            int v = (int)((s + 1.0f) * 127.5f);
            if (v < 0) v = 0; else if (v > 255) v = 255;
            wave[i] = (uint8_t)v;
        }
        return count;
    }

private:
    static constexpr int RING_SIZE = 8192;  // power of 2, >= 2*FFT_SIZE
    static constexpr int RING_MASK = RING_SIZE - 1;

    // Ring buffer (SPSC: audio thread writes, viz thread reads)
    float ringBuf_[RING_SIZE];
    int writePos_ = 0;    // only written by audio thread
    std::atomic<int> samplesAvailable_{0};

    // FFT working buffers
    float window_[FFT_SIZE];
    float inputBuf_[FFT_SIZE];
    float fftOut_[FFT_SIZE];
    float magnitudes_[HALF_FFT + 1];

    // Smoothed output bands (persisted across frames for attack/decay)
    float smoothBands_[NUM_BANDS];

    // Log-frequency band edges (FFT bin indices)
    int bandEdges_[NUM_BANDS + 1];

    void computeBandEdges() {
        // Power-curve mapping: more resolution in bass, less in treble
        // bin = 1 + (HALF_FFT-1) * (b/NUM_BANDS)^2.0
        for (int b = 0; b <= NUM_BANDS; b++) {
            float t = (float)b / NUM_BANDS;
            bandEdges_[b] = 1 + (int)(powf(t, 2.0f) * (HALF_FFT - 1));
        }
        // Ensure monotonic and non-empty
        for (int b = 1; b <= NUM_BANDS; b++) {
            if (bandEdges_[b] <= bandEdges_[b - 1]) {
                bandEdges_[b] = bandEdges_[b - 1] + 1;
            }
        }
    }

    // ── Radix-2 real FFT via "pack two reals into one complex" ──

    static void realFFT(const float* input, float* output, int N) {
        const int M = N / 2;

        // Pack: z[k] = input[2k] + j * input[2k+1]
        float z[4096]; // M*2 complex values (M <= 1024 for N=2048)
        for (int k = 0; k < M; k++) {
            z[2 * k]     = input[2 * k];
            z[2 * k + 1] = input[2 * k + 1];
        }

        // Bit-reversal permutation
        for (int i = 1, j = 0; i < M; i++) {
            int bit = M >> 1;
            for (; j & bit; bit >>= 1) j ^= bit;
            j ^= bit;
            if (i < j) {
                std::swap(z[2 * i],     z[2 * j]);
                std::swap(z[2 * i + 1], z[2 * j + 1]);
            }
        }

        // Cooley-Tukey butterfly
        for (int len = 2; len <= M; len <<= 1) {
            float ang = -2.0f * (float)M_PI / len;
            float wRe = cosf(ang), wIm = sinf(ang);
            for (int i = 0; i < M; i += len) {
                float curRe = 1.0f, curIm = 0.0f;
                for (int j = 0; j < len / 2; j++) {
                    int u = i + j, v = i + j + len / 2;
                    float tRe = z[2 * v]     * curRe - z[2 * v + 1] * curIm;
                    float tIm = z[2 * v]     * curIm + z[2 * v + 1] * curRe;
                    z[2 * v]     = z[2 * u]     - tRe;
                    z[2 * v + 1] = z[2 * u + 1] - tIm;
                    z[2 * u]     += tRe;
                    z[2 * u + 1] += tIm;
                    float newRe = curRe * wRe - curIm * wIm;
                    curIm = curRe * wIm + curIm * wRe;
                    curRe = newRe;
                }
            }
        }

        // Unpack N/2-complex → N-real FFT
        // output layout: [DC, Nyquist, Re[1], Im[1], Re[2], Im[2], ...]
        output[0] = z[0] + z[1];   // DC (real)
        output[1] = z[0] - z[1];   // Nyquist (real)
        for (int k = 1; k < M; k++) {
            int mk = M - k;
            float eRe =  0.5f * (z[2 * k]     + z[2 * mk]);
            float eIm =  0.5f * (z[2 * k + 1] - z[2 * mk + 1]);
            float oRe =  0.5f * (z[2 * k + 1] + z[2 * mk + 1]);
            float oIm = -0.5f * (z[2 * k]     - z[2 * mk]);
            float ang2 = -2.0f * (float)M_PI * k / N;
            float wR = cosf(ang2), wI = sinf(ang2);
            float tRe = oRe * wR - oIm * wI;
            float tIm = oRe * wI + oIm * wR;
            output[2 * k]     = eRe + tRe;
            output[2 * k + 1] = eIm + tIm;
        }
    }
};
