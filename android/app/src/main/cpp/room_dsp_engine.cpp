#include "room_dsp_engine.h"
#include <cstring>
#include <algorithm>

RoomDSPEngine::RoomDSPEngine()
    : sampleRate_(48000), channels_(2) {
}

void RoomDSPEngine::init(int sampleRate, int channels) {
    sampleRate_ = sampleRate;
    channels_ = channels;
    reverb_.init(sampleRate);
    crossfeed_.init(sampleRate);
    // Stereo expander is stateless except for smoothing, no init needed
    // Default crossfeed to Chu Moy preset
    crossfeed_.configure(Crossfeed::kChuMoyCutoff, Crossfeed::kChuMoyFeed);
}

void RoomDSPEngine::reset() {
    reverb_.reset();
    stereoExpander_.reset();
    crossfeed_.reset();
}

void RoomDSPEngine::process(float* buffer, int numFrames) {
    if (channels_ != 2 || numFrames <= 0) return;

    bool doExpand = stereoExpandEnabled_.load(std::memory_order_relaxed);
    bool doCrossfeed = crossfeedEnabled_.load(std::memory_order_relaxed);
    bool doReverb = reverbEnabled_.load(std::memory_order_relaxed);

    // Early out if nothing is enabled
    if (!doExpand && !doCrossfeed && !doReverb) return;

    // Deinterleave to separate L/R channels for processing
    // Stack-allocate for small buffers, heap for large
    constexpr int STACK_LIMIT = 2048;
    float stackL[STACK_LIMIT], stackR[STACK_LIMIT];
    float* left;
    float* right;
    float* heapBuf = nullptr;

    if (numFrames <= STACK_LIMIT) {
        left = stackL;
        right = stackR;
    } else {
        heapBuf = new float[numFrames * 2];
        left = heapBuf;
        right = heapBuf + numFrames;
    }

    // Deinterleave [L0,R0,L1,R1,...] -> separate L[] and R[]
    for (int i = 0; i < numFrames; i++) {
        left[i]  = buffer[i * 2];
        right[i] = buffer[i * 2 + 1];
    }

    // Processing chain: Stereo Expand -> Crossfeed -> Reverb
    if (doExpand) {
        stereoExpander_.process(left, right, numFrames);
    }
    if (doCrossfeed) {
        crossfeed_.process(left, right, numFrames);
    }
    if (doReverb) {
        reverb_.process(left, right, numFrames);
    }

    // Re-interleave back to [L0,R0,L1,R1,...] with safety clamp
    for (int i = 0; i < numFrames; i++) {
        buffer[i * 2]     = std::clamp(left[i],  -4.0f, 4.0f);
        buffer[i * 2 + 1] = std::clamp(right[i], -4.0f, 4.0f);
    }

    delete[] heapBuf;
}
