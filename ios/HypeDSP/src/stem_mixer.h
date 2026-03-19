#pragma once
#include <cstring>
#include <cmath>
#include <atomic>
#include <algorithm>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#ifdef __ANDROID__
#include <android/log.h>
#define STEM_LOGI(...) __android_log_print(ANDROID_LOG_INFO, "StemMixer", __VA_ARGS__)
#define STEM_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "StemMixer", __VA_ARGS__)
#else
#include <cstdio>
#define STEM_LOGI(...) do { fprintf(stderr, "StemMixer: "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while(0)
#define STEM_LOGE(...) do { fprintf(stderr, "StemMixer ERROR: "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while(0)
#endif

// 4-track stem mixer with memory-mapped WAV file I/O.
//
// Loads 4 pre-separated stem WAV files (vocals, drums, bass, other),
// reads them in sync, and mixes to stereo with per-stem volume/mute/solo.
//
// WAV files must be: 32-bit float, stereo, same sample rate and length.
// Standard 44-byte WAV header expected (no extended chunks).
//
// All controls are atomic — safe to update from UI thread while audio
// thread calls mix(). Lock-free design matches the DSP engine pattern.
class StemMixer {
public:
    static constexpr int NUM_STEMS = 4;
    static constexpr int STEM_VOCALS = 0;
    static constexpr int STEM_DRUMS  = 1;
    static constexpr int STEM_BASS   = 2;
    static constexpr int STEM_OTHER  = 3;

    StemMixer() = default;

    ~StemMixer() {
        unloadStems();
    }

    // Load 4 WAV files (float32 stereo). Returns true if all loaded OK.
    bool loadStems(const char* paths[NUM_STEMS]) {
        unloadStems();

        for (int i = 0; i < NUM_STEMS; i++) {
            if (!loadWav(paths[i], stems_[i])) {
                STEM_LOGE("Failed to load stem %d: %s", i, paths[i]);
                unloadStems();
                return false;
            }
        }

        // Validate: all stems must have same frame count
        size_t frames0 = stems_[0].totalFrames;
        for (int i = 1; i < NUM_STEMS; i++) {
            if (stems_[i].totalFrames != frames0) {
                STEM_LOGE("Stem %d frame count mismatch: %zu vs %zu",
                          i, stems_[i].totalFrames, frames0);
                unloadStems();
                return false;
            }
        }

        readPos_.store(0, std::memory_order_relaxed);
        loaded_.store(true, std::memory_order_release);
        STEM_LOGI("Loaded %d stems, %zu frames each", NUM_STEMS, frames0);
        return true;
    }

    void unloadStems() {
        loaded_.store(false, std::memory_order_release);
        for (int i = 0; i < NUM_STEMS; i++) {
            unloadWav(stems_[i]);
        }
        readPos_.store(0, std::memory_order_relaxed);
    }

    // Mix stems into interleaved stereo output buffer, replacing its contents.
    // Called from audio thread — must be lock-free.
    void mix(float* output, int numFrames) {
        if (!loaded_.load(std::memory_order_acquire)) return;

        size_t pos = readPos_.load(std::memory_order_relaxed);
        size_t total = stems_[0].totalFrames;
        if (pos >= total) {
            // End of stems — fill silence
            std::memset(output, 0, numFrames * 2 * sizeof(float));
            return;
        }

        // Determine solo state
        bool hasSolo = anySoloed();

        int framesToMix = std::min((int)(total - pos), numFrames);

        // Zero output first
        std::memset(output, 0, numFrames * 2 * sizeof(float));

        for (int s = 0; s < NUM_STEMS; s++) {
            bool muted = stems_[s].muted.load(std::memory_order_relaxed);
            bool soloed = stems_[s].soloed.load(std::memory_order_relaxed);
            float vol = stems_[s].volume.load(std::memory_order_relaxed);

            // Skip if muted, or if solo mode active and this stem isn't soloed
            if (muted || (hasSolo && !soloed)) continue;

            const float* data = stems_[s].data + pos * 2;  // stereo interleaved
            for (int i = 0; i < framesToMix; i++) {
                output[i * 2]     += data[i * 2]     * vol;
                output[i * 2 + 1] += data[i * 2 + 1] * vol;
            }
        }

        readPos_.store(pos + framesToMix, std::memory_order_relaxed);
    }

    void seek(size_t samplePos) {
        if (!loaded_.load(std::memory_order_acquire)) return;
        size_t total = stems_[0].totalFrames;
        readPos_.store(std::min(samplePos, total), std::memory_order_relaxed);
    }

    void setVolume(int stem, float vol) {
        if (stem >= 0 && stem < NUM_STEMS)
            stems_[stem].volume.store(std::max(0.0f, std::min(2.0f, vol)),
                                       std::memory_order_relaxed);
    }

    void setMute(int stem, bool muted) {
        if (stem >= 0 && stem < NUM_STEMS)
            stems_[stem].muted.store(muted, std::memory_order_relaxed);
    }

    void setSolo(int stem, bool soloed) {
        if (stem >= 0 && stem < NUM_STEMS)
            stems_[stem].soloed.store(soloed, std::memory_order_relaxed);
    }

    bool isLoaded() const {
        return loaded_.load(std::memory_order_acquire);
    }

    size_t getPosition() const {
        return readPos_.load(std::memory_order_relaxed);
    }

    size_t getTotalFrames() const {
        if (!loaded_.load(std::memory_order_acquire)) return 0;
        return stems_[0].totalFrames;
    }

    int getSampleRate() const {
        if (!loaded_.load(std::memory_order_acquire)) return 0;
        return stems_[0].sampleRate;
    }

private:
    struct StemTrack {
        int fd = -1;
        void* mapPtr = MAP_FAILED;   // raw mmap address (includes WAV header)
        size_t mapSize = 0;
        float* data = nullptr;       // PCM data start (after header)
        size_t totalFrames = 0;      // number of stereo frames
        int sampleRate = 0;
        std::atomic<float> volume{1.0f};
        std::atomic<bool> muted{false};
        std::atomic<bool> soloed{false};
    };

    StemTrack stems_[NUM_STEMS];
    std::atomic<size_t> readPos_{0};
    std::atomic<bool> loaded_{false};

    bool anySoloed() const {
        for (int i = 0; i < NUM_STEMS; i++) {
            if (stems_[i].soloed.load(std::memory_order_relaxed)) return true;
        }
        return false;
    }

    // Standard WAV header (44 bytes)
    struct WavHeader {
        char riff[4];           // "RIFF"
        uint32_t fileSize;      // file size - 8
        char wave[4];           // "WAVE"
        char fmt[4];            // "fmt "
        uint32_t fmtSize;       // format chunk size (16 for PCM)
        uint16_t audioFormat;   // 1=PCM, 3=IEEE float
        uint16_t numChannels;
        uint32_t sampleRate;
        uint32_t byteRate;
        uint16_t blockAlign;
        uint16_t bitsPerSample;
    };

    bool loadWav(const char* path, StemTrack& track) {
        track.fd = open(path, O_RDONLY);
        if (track.fd < 0) {
            STEM_LOGE("Cannot open: %s", path);
            return false;
        }

        struct stat st;
        if (fstat(track.fd, &st) != 0 || st.st_size < 44) {
            STEM_LOGE("File too small or stat failed: %s", path);
            close(track.fd);
            track.fd = -1;
            return false;
        }

        track.mapSize = st.st_size;
        track.mapPtr = mmap(nullptr, track.mapSize, PROT_READ, MAP_PRIVATE, track.fd, 0);
        if (track.mapPtr == MAP_FAILED) {
            STEM_LOGE("mmap failed: %s", path);
            close(track.fd);
            track.fd = -1;
            return false;
        }

        // Parse header
        auto* hdr = static_cast<const uint8_t*>(track.mapPtr);

        // Find "data" chunk (skip any extended fmt or other chunks)
        size_t dataOffset = 0;
        size_t dataSize = 0;
        int sampleRate = 0;
        int numChannels = 0;
        int bitsPerSample = 0;
        uint16_t audioFormat = 0;

        // Validate RIFF/WAVE
        if (memcmp(hdr, "RIFF", 4) != 0 || memcmp(hdr + 8, "WAVE", 4) != 0) {
            STEM_LOGE("Not a WAV file: %s", path);
            munmap(track.mapPtr, track.mapSize);
            track.mapPtr = MAP_FAILED;
            close(track.fd);
            track.fd = -1;
            return false;
        }

        // Walk chunks
        size_t offset = 12;
        while (offset + 8 <= track.mapSize) {
            const char* chunkId = reinterpret_cast<const char*>(hdr + offset);
            uint32_t chunkSize;
            memcpy(&chunkSize, hdr + offset + 4, 4);

            if (memcmp(chunkId, "fmt ", 4) == 0 && chunkSize >= 16) {
                memcpy(&audioFormat, hdr + offset + 8, 2);
                memcpy(&numChannels, hdr + offset + 10, 2);
                memcpy(&sampleRate, hdr + offset + 12, 4);
                memcpy(&bitsPerSample, hdr + offset + 22, 2);
            } else if (memcmp(chunkId, "data", 4) == 0) {
                dataOffset = offset + 8;
                dataSize = chunkSize;
                break;
            }

            offset += 8 + chunkSize;
            if (chunkSize & 1) offset++;  // chunks are word-aligned
        }

        if (dataOffset == 0 || dataSize == 0) {
            STEM_LOGE("No data chunk found: %s", path);
            munmap(track.mapPtr, track.mapSize);
            track.mapPtr = MAP_FAILED;
            close(track.fd);
            track.fd = -1;
            return false;
        }

        // Validate format: must be float32 stereo
        if (audioFormat != 3 || bitsPerSample != 32 || numChannels != 2) {
            STEM_LOGE("WAV must be float32 stereo (got fmt=%d bits=%d ch=%d): %s",
                      audioFormat, bitsPerSample, numChannels, path);
            munmap(track.mapPtr, track.mapSize);
            track.mapPtr = MAP_FAILED;
            close(track.fd);
            track.fd = -1;
            return false;
        }

        track.data = reinterpret_cast<float*>(
            static_cast<uint8_t*>(track.mapPtr) + dataOffset);
        track.totalFrames = dataSize / (numChannels * sizeof(float));
        track.sampleRate = sampleRate;
        track.volume.store(1.0f, std::memory_order_relaxed);
        track.muted.store(false, std::memory_order_relaxed);
        track.soloed.store(false, std::memory_order_relaxed);

        STEM_LOGI("Loaded WAV: %s (%d Hz, %zu frames)", path, sampleRate, track.totalFrames);
        return true;
    }

    void unloadWav(StemTrack& track) {
        if (track.mapPtr != MAP_FAILED) {
            munmap(track.mapPtr, track.mapSize);
            track.mapPtr = MAP_FAILED;
        }
        if (track.fd >= 0) {
            close(track.fd);
            track.fd = -1;
        }
        track.data = nullptr;
        track.totalFrames = 0;
        track.sampleRate = 0;
    }
};
