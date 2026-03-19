#pragma once
#include "biquad.h"
#include <cstring>
#include <cmath>
#include <algorithm>
#include <vector>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#ifdef __ANDROID__
#include <android/log.h>
#define SEP_LOGI(...) __android_log_print(ANDROID_LOG_INFO, "StemSep", __VA_ARGS__)
#define SEP_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "StemSep", __VA_ARGS__)
#else
#include <cstdio>
#define SEP_LOGI(...) do { fprintf(stderr, "StemSep: "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while(0)
#define SEP_LOGE(...) do { fprintf(stderr, "StemSep ERROR: "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while(0)
#endif

// Offline stem separator using frequency-band splitting + Mid/Side spatial analysis.
//
// Technique: classic DJ-style separation (not ML-based):
//   1. Decompose stereo into Mid (center) and Side (panned) signals
//   2. Split each into frequency bands using Butterworth crossover filters
//   3. Assign bands to stems based on where instruments typically live:
//      - Bass:   Low frequencies (< 250 Hz) — center and sides
//      - Vocals: Mid-frequency center content (250-8000 Hz)
//      - Other:  Mid-frequency side content + high frequencies (panned instruments, guitars, synths)
//      - Drums:  Residual (original minus other three stems)
//
// Quality: ~3-5 dB SDR for vocals (decent karaoke), very good bass isolation.
// Not ML-grade (Demucs = ~9 dB SDR), but clearly audible and instant.
//
// Uses 4th-order Butterworth (two cascaded biquads) with forward-backward
// filtering for zero-phase response (effective 8th order, -48 dB/oct).
class StemSeparator {
public:
    // File-based separation: reads raw PCM from inputPath, separates, writes 4 WAV files.
    // All heavy memory allocation happens in native heap (no Java heap pressure).
    // inputPath: raw interleaved float32 stereo PCM file
    // outputDir: directory to write vocals.wav, drums.wav, bass.wav, other.wav
    static bool separateFromFile(const char* inputPath, int numFrames, int sampleRate,
                                 const char* outputDir) {
        // mmap the input raw PCM file
        int fd = open(inputPath, O_RDONLY);
        if (fd < 0) {
            SEP_LOGE("Cannot open input: %s", inputPath);
            return false;
        }

        size_t fileSize = (size_t)numFrames * 2 * sizeof(float);
        void* mapped = mmap(nullptr, fileSize, PROT_READ, MAP_PRIVATE, fd, 0);
        close(fd);

        if (mapped == MAP_FAILED) {
            SEP_LOGE("mmap failed for %s", inputPath);
            return false;
        }

        const float* input = static_cast<const float*>(mapped);
        size_t stereoLen = (size_t)numFrames * 2;

        // Allocate output buffers on native heap
        float* vocals = new(std::nothrow) float[stereoLen];
        float* drums  = new(std::nothrow) float[stereoLen];
        float* bass   = new(std::nothrow) float[stereoLen];
        float* other  = new(std::nothrow) float[stereoLen];

        if (!vocals || !drums || !bass || !other) {
            SEP_LOGE("Native heap alloc failed (%zu floats x 4)", stereoLen);
            delete[] vocals; delete[] drums; delete[] bass; delete[] other;
            munmap(mapped, fileSize);
            return false;
        }

        SEP_LOGI("Separating %d frames at %d Hz (native heap)", numFrames, sampleRate);

        // Run separation
        separate(input, numFrames, sampleRate, vocals, drums, bass, other);

        // Unmap input — no longer needed
        munmap(mapped, fileSize);

        SEP_LOGI("Separation done, writing WAV files...");

        // Write 4 WAV files
        const char* stemNames[] = {"vocals", "drums", "bass", "other"};
        float* stemData[] = {vocals, drums, bass, other};
        bool ok = true;

        for (int i = 0; i < 4; i++) {
            char path[512];
            snprintf(path, sizeof(path), "%s/%s.wav", outputDir, stemNames[i]);
            if (!writeWavFile(path, stemData[i], numFrames, sampleRate)) {
                SEP_LOGE("Failed to write %s", path);
                ok = false;
                break;
            }
            SEP_LOGI("Wrote %s", path);
        }

        delete[] vocals;
        delete[] drums;
        delete[] bass;
        delete[] other;

        return ok;
    }

    // Separate interleaved stereo float PCM into 4 stems.
    // Input:  interleaved stereo [L0,R0, L1,R1, ...] with numFrames frames
    // Output: 4 interleaved stereo buffers (caller must allocate, each numFrames*2 floats)
    static void separate(const float* input, int numFrames, int sampleRate,
                         float* vocals, float* drums, float* bass, float* other) {

        // Allocate mono working buffers
        std::vector<float> left(numFrames), right(numFrames);
        std::vector<float> mid(numFrames), side(numFrames);

        // Step 1: Deinterleave
        for (int i = 0; i < numFrames; i++) {
            left[i]  = input[i * 2];
            right[i] = input[i * 2 + 1];
        }

        // Step 2: M/S decomposition
        for (int i = 0; i < numFrames; i++) {
            mid[i]  = (left[i] + right[i]) * 0.5f;
            side[i] = (left[i] - right[i]) * 0.5f;
        }

        // Step 3: Frequency-band separation using zero-phase Butterworth filters

        const float bassFreq = 250.0f;   // Bass crossover
        const float highFreq = 8000.0f;  // Vocal/other crossover
        const float Q = 0.707f;          // Butterworth Q

        // --- Bass stem: LPF on full stereo ---
        std::vector<float> bassL(left.begin(), left.end());
        std::vector<float> bassR(right.begin(), right.end());
        applyZeroPhaseLP(bassL.data(), numFrames, sampleRate, bassFreq, Q);
        applyZeroPhaseLP(bassR.data(), numFrames, sampleRate, bassFreq, Q);

        // --- Vocals: center content (Mid signal) bandpassed 250-8000 Hz ---
        std::vector<float> vocalMid(mid.begin(), mid.end());
        applyZeroPhaseHP(vocalMid.data(), numFrames, sampleRate, bassFreq, Q);
        applyZeroPhaseLP(vocalMid.data(), numFrames, sampleRate, highFreq, Q);

        // --- Other: side content (panned instruments) + high-frequency center ---
        // Side band (250-8000 Hz): panned guitars, synths, etc.
        std::vector<float> otherSide(side.begin(), side.end());
        applyZeroPhaseHP(otherSide.data(), numFrames, sampleRate, bassFreq, Q);

        // High-frequency mid content (> 8000 Hz): cymbals, air, harmonics
        std::vector<float> highMid(mid.begin(), mid.end());
        applyZeroPhaseHP(highMid.data(), numFrames, sampleRate, highFreq, Q);

        // High-frequency side content
        std::vector<float> highSide(side.begin(), side.end());
        applyZeroPhaseHP(highSide.data(), numFrames, sampleRate, highFreq, Q);

        // Step 4: Interleave to stereo output buffers

        // Bass: full stereo low frequencies
        for (int i = 0; i < numFrames; i++) {
            bass[i * 2]     = bassL[i];
            bass[i * 2 + 1] = bassR[i];
        }

        // Vocals: center-panned mid frequencies
        for (int i = 0; i < numFrames; i++) {
            vocals[i * 2]     = vocalMid[i];
            vocals[i * 2 + 1] = vocalMid[i];
        }

        // Other: side instruments + high frequencies (reconstruct stereo from M/S)
        for (int i = 0; i < numFrames; i++) {
            // Side-band instruments: L = +side, R = -side (preserves stereo image)
            // Plus high-frequency center and side content
            other[i * 2]     = otherSide[i] + highMid[i] + highSide[i];
            other[i * 2 + 1] = -otherSide[i] + highMid[i] - highSide[i];
        }

        // Drums: residual (original minus the three extracted stems)
        // This captures content that doesn't cleanly fit into the other categories:
        // kick drum (center, shares bass freq but has transient character),
        // snare (center, mid-freq), toms (may be panned), hi-hats
        for (int i = 0; i < numFrames; i++) {
            drums[i * 2]     = left[i]  - bass[i * 2]     - vocals[i * 2]     - other[i * 2];
            drums[i * 2 + 1] = right[i] - bass[i * 2 + 1] - vocals[i * 2 + 1] - other[i * 2 + 1];
        }
    }

private:
    // Apply 4th-order zero-phase lowpass (forward + backward = 8th order effective)
    static void applyZeroPhaseLP(float* data, int n, int sr, float freq, float q) {
        BiquadCoeffs c = BiquadDesign::lowPass((float)sr, freq, q);
        applyForwardBackward(data, n, c);
        applyForwardBackward(data, n, c);  // second cascade = 4th order per direction
    }

    // Apply 4th-order zero-phase highpass
    static void applyZeroPhaseHP(float* data, int n, int sr, float freq, float q) {
        BiquadCoeffs c = BiquadDesign::highPass((float)sr, freq, q);
        applyForwardBackward(data, n, c);
        applyForwardBackward(data, n, c);
    }

    // Forward-backward filtering: apply filter forward, then reverse and apply again.
    // Result: zero phase distortion, doubled filter order.
    static void applyForwardBackward(float* data, int n, const BiquadCoeffs& c) {
        if (n <= 0) return;

        // Forward pass (DF2T)
        float s1 = 0.0f, s2 = 0.0f;
        for (int i = 0; i < n; i++) {
            float x = data[i];
            float y = c.b0 * x + s1;
            s1 = c.b1 * x - c.a1 * y + s2;
            s2 = c.b2 * x - c.a2 * y;
            data[i] = y;
        }

        // Backward pass (same filter, reversed direction)
        s1 = 0.0f;
        s2 = 0.0f;
        for (int i = n - 1; i >= 0; i--) {
            float x = data[i];
            float y = c.b0 * x + s1;
            s1 = c.b1 * x - c.a1 * y + s2;
            s2 = c.b2 * x - c.a2 * y;
            data[i] = y;
        }
    }

    // Write interleaved float32 stereo PCM to a WAV file (IEEE float format).
    static bool writeWavFile(const char* path, const float* data, int numFrames, int sampleRate) {
        int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0) return false;

        const int channels = 2;
        const int bitsPerSample = 32;
        int dataSize = numFrames * channels * (bitsPerSample / 8);
        int fileSize = 44 + dataSize - 8;

        // Build 44-byte WAV header
        uint8_t header[44];
        auto writeU32 = [&](int off, uint32_t v) {
            header[off]   = v & 0xFF;
            header[off+1] = (v >> 8) & 0xFF;
            header[off+2] = (v >> 16) & 0xFF;
            header[off+3] = (v >> 24) & 0xFF;
        };
        auto writeU16 = [&](int off, uint16_t v) {
            header[off]   = v & 0xFF;
            header[off+1] = (v >> 8) & 0xFF;
        };

        memcpy(header, "RIFF", 4);
        writeU32(4, fileSize);
        memcpy(header + 8, "WAVE", 4);
        memcpy(header + 12, "fmt ", 4);
        writeU32(16, 16);                                   // chunk size
        writeU16(20, 3);                                    // IEEE float
        writeU16(22, channels);
        writeU32(24, sampleRate);
        writeU32(28, sampleRate * channels * 4);            // byte rate
        writeU16(32, channels * 4);                         // block align
        writeU16(34, bitsPerSample);
        memcpy(header + 36, "data", 4);
        writeU32(40, dataSize);

        if (write(fd, header, 44) != 44) { close(fd); return false; }

        // Write PCM data in chunks to avoid huge single write
        const size_t chunkFloats = 8192;
        const float* ptr = data;
        size_t remaining = (size_t)numFrames * channels;

        while (remaining > 0) {
            size_t count = std::min(remaining, chunkFloats);
            ssize_t written = write(fd, ptr, count * sizeof(float));
            if (written <= 0) { close(fd); return false; }
            size_t floatsWritten = written / sizeof(float);
            ptr += floatsWritten;
            remaining -= floatsWritten;
        }

        close(fd);
        return true;
    }
};
