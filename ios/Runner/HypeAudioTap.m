#import "HypeAudioTap.h"
#import <MediaToolbox/MediaToolbox.h>
#import <Accelerate/Accelerate.h>
#import <HypeDSP/dsp_bridge.h>
#import <os/lock.h>

#define VIZ_CAPTURE_SIZE 1024
#define MAX_SCRATCH_FRAMES 8192

// Context stored in each MTAudioProcessingTap
typedef struct {
    void *dspHandle;
    float *scratchBuffer;     // interleave buffer (MAX_SCRATCH_FRAMES * 2)
    int sampleRate;
    int channels;

    // Visualization capture (lock-free: audio thread writes, main thread reads)
    uint8_t vizWaveform[VIZ_CAPTURE_SIZE];
    uint8_t vizFft[VIZ_CAPTURE_SIZE];
    int vizWaveformReady;     // atomic flag
    int vizFftReady;          // atomic flag
    int vizEnabled;           // atomic flag

    // FFT scratch buffers
    float fftInput[VIZ_CAPTURE_SIZE];
    FFTSetup fftSetup;
    float fftWindow[VIZ_CAPTURE_SIZE];
    float fftRealp[VIZ_CAPTURE_SIZE / 2];
    float fftImagp[VIZ_CAPTURE_SIZE / 2];
} TapContext;

// Shared latest context (points to whichever tap is active)
static TapContext * volatile sActiveContext = NULL;
// Global enabled state — survives tap context switches
static volatile int sVizEnabledGlobal = 0;

#pragma mark - MTAudioProcessingTap Callbacks

static void tap_Init(MTAudioProcessingTapRef tap, void *clientInfo, void **tapStorageOut) {
    TapContext *ctx = (TapContext *)calloc(1, sizeof(TapContext));
    ctx->dspHandle = clientInfo;
    ctx->scratchBuffer = (float *)calloc(MAX_SCRATCH_FRAMES * 2, sizeof(float));
    ctx->sampleRate = 44100;
    ctx->channels = 2;

    // FFT setup
    int log2n = (int)log2f((float)VIZ_CAPTURE_SIZE);
    ctx->fftSetup = vDSP_create_fftsetup(log2n, kFFTRadix2);
    vDSP_hann_window(ctx->fftWindow, VIZ_CAPTURE_SIZE, vDSP_HANN_NORM);

    *tapStorageOut = ctx;
}

static void tap_Finalize(MTAudioProcessingTapRef tap) {
    TapContext *ctx = (TapContext *)MTAudioProcessingTapGetStorage(tap);
    if (ctx == sActiveContext) {
        sActiveContext = NULL;
    }
    if (ctx->fftSetup) vDSP_destroy_fftsetup(ctx->fftSetup);
    free(ctx->scratchBuffer);
    free(ctx);
}

static void tap_Prepare(MTAudioProcessingTapRef tap,
                         CMItemCount maxFrames,
                         const AudioStreamBasicDescription *processingFormat) {
    TapContext *ctx = (TapContext *)MTAudioProcessingTapGetStorage(tap);
    ctx->sampleRate = (int)processingFormat->mSampleRate;
    ctx->channels = (int)processingFormat->mChannelsPerFrame;

    // Reinit DSP engine for this sample rate
    if (ctx->dspHandle) {
        dsp_reinit(ctx->dspHandle, ctx->sampleRate, ctx->channels);
    }

    // Propagate global visualization state to this new context
    __atomic_store_n(&ctx->vizEnabled, sVizEnabledGlobal, __ATOMIC_RELEASE);

    sActiveContext = ctx;
}

static void tap_Unprepare(MTAudioProcessingTapRef tap) {
    TapContext *ctx = (TapContext *)MTAudioProcessingTapGetStorage(tap);
    if (ctx == sActiveContext) {
        sActiveContext = NULL;
    }
}

static void captureVisualization(TapContext *ctx, const float *interleavedData, int numFrames) {
    // Downsample stereo interleaved PCM to VIZ_CAPTURE_SIZE mono uint8 samples
    // Format matches Android Visualizer: unsigned bytes 0-255, silence = 128
    int step = (numFrames > VIZ_CAPTURE_SIZE) ? (numFrames / VIZ_CAPTURE_SIZE) : 1;
    int count = (numFrames > VIZ_CAPTURE_SIZE) ? VIZ_CAPTURE_SIZE : numFrames;

    for (int i = 0; i < count; i++) {
        int srcIdx = i * step * 2; // stereo interleaved
        float l = interleavedData[srcIdx];
        float r = interleavedData[srcIdx + 1];
        float mono = (l + r) * 0.5f;
        // Clamp to [-1, 1] and convert to unsigned byte [0, 255]
        if (mono < -1.0f) mono = -1.0f;
        if (mono > 1.0f) mono = 1.0f;
        ctx->vizWaveform[i] = (uint8_t)((mono + 1.0f) * 127.5f);
        ctx->fftInput[i] = mono;
    }
    // Pad remainder
    for (int i = count; i < VIZ_CAPTURE_SIZE; i++) {
        ctx->vizWaveform[i] = 128; // silence
        ctx->fftInput[i] = 0.0f;
    }
    __atomic_store_n(&ctx->vizWaveformReady, 1, __ATOMIC_RELEASE);

    // Compute FFT → magnitude bytes matching Android Visualizer format
    if (ctx->fftSetup) {
        float windowed[VIZ_CAPTURE_SIZE];
        vDSP_vmul(ctx->fftInput, 1, ctx->fftWindow, 1, windowed, 1, VIZ_CAPTURE_SIZE);

        DSPSplitComplex splitComplex = { ctx->fftRealp, ctx->fftImagp };
        vDSP_ctoz((DSPComplex *)windowed, 2, &splitComplex, 1, VIZ_CAPTURE_SIZE / 2);

        int log2n = (int)log2f((float)VIZ_CAPTURE_SIZE);
        vDSP_fft_zrip(ctx->fftSetup, &splitComplex, 1, log2n, FFT_FORWARD);

        // Convert FFT output to magnitude bytes [0-255] per frequency bin.
        // vDSP_fft_zrip output is scaled by 2x, so divide by N to normalize.
        float scale = 1.0f / (float)VIZ_CAPTURE_SIZE;
        int half = VIZ_CAPTURE_SIZE / 2;

        // First pass: find peak magnitude for adaptive normalization
        float peakMag = 0.0001f;
        for (int i = 1; i < half; i++) { // skip DC bin
            float re = ctx->fftRealp[i] * scale;
            float im = ctx->fftImagp[i] * scale;
            float mag = sqrtf(re * re + im * im);
            if (mag > peakMag) peakMag = mag;
        }

        // Second pass: normalize relative to peak, with dB mapping
        for (int i = 0; i < half; i++) {
            float re = ctx->fftRealp[i] * scale;
            float im = ctx->fftImagp[i] * scale;
            float mag = sqrtf(re * re + im * im);
            // dB relative to peak: 0 dB at peak, negative below
            float dbVal = 20.0f * log10f(mag / peakMag + 1e-10f);
            // Map [-40 dB, 0 dB] to [0, 255]
            float norm = (dbVal + 40.0f) / 40.0f;
            if (norm < 0.0f) norm = 0.0f;
            if (norm > 1.0f) norm = 1.0f;
            ctx->vizFft[i * 2]     = (uint8_t)(norm * 255.0f);
            ctx->vizFft[i * 2 + 1] = 0;
        }
        __atomic_store_n(&ctx->vizFftReady, 1, __ATOMIC_RELEASE);
    }
}

static void tap_Process(MTAudioProcessingTapRef tap,
                         CMItemCount numberFrames,
                         MTAudioProcessingTapFlags flags,
                         AudioBufferList *bufferListInOut,
                         CMItemCount *numberFramesOut,
                         MTAudioProcessingTapFlags *flagsOut) {
    TapContext *ctx = (TapContext *)MTAudioProcessingTapGetStorage(tap);

    OSStatus status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames,
                                                          bufferListInOut,
                                                          flagsOut, NULL, numberFramesOut);
    if (status != noErr) return;

    int frames = (int)*numberFramesOut;
    if (frames <= 0 || !ctx->dspHandle) return;

    if (bufferListInOut->mNumberBuffers == 1) {
        // Interleaved stereo float
        float *data = (float *)bufferListInOut->mBuffers[0].mData;
        dsp_process_float(ctx->dspHandle, data, frames);

        if (__atomic_load_n(&ctx->vizEnabled, __ATOMIC_ACQUIRE)) {
            captureVisualization(ctx, data, frames);
        }
    } else if (bufferListInOut->mNumberBuffers >= 2) {
        // Non-interleaved: separate L/R buffers
        float *left  = (float *)bufferListInOut->mBuffers[0].mData;
        float *right = (float *)bufferListInOut->mBuffers[1].mData;

        int clampedFrames = (frames > MAX_SCRATCH_FRAMES) ? MAX_SCRATCH_FRAMES : frames;

        for (int i = 0; i < clampedFrames; i++) {
            ctx->scratchBuffer[i * 2]     = left[i];
            ctx->scratchBuffer[i * 2 + 1] = right[i];
        }

        dsp_process_float(ctx->dspHandle, ctx->scratchBuffer, clampedFrames);

        if (__atomic_load_n(&ctx->vizEnabled, __ATOMIC_ACQUIRE)) {
            captureVisualization(ctx, ctx->scratchBuffer, clampedFrames);
        }

        for (int i = 0; i < clampedFrames; i++) {
            left[i]  = ctx->scratchBuffer[i * 2];
            right[i] = ctx->scratchBuffer[i * 2 + 1];
        }
    }
}

#pragma mark - HypeAudioTap

@implementation HypeAudioTap {
    void *_dspHandle;
}

+ (instancetype)shared {
    static HypeAudioTap *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HypeAudioTap alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _dspHandle = NULL;
    }
    return self;
}

- (void)setDspHandle:(void *)handle {
    _dspHandle = handle;
}

- (void)installTapOnPlayerItem:(AVPlayerItem *)playerItem {
    if (!_dspHandle) return;

    AVAsset *asset = playerItem.asset;
    void *handle = _dspHandle;

    [asset loadTracksWithMediaType:AVMediaTypeAudio
                 completionHandler:^(NSArray<AVAssetTrack *> * _Nullable tracks,
                                     NSError * _Nullable error) {
        if (error || tracks.count == 0) return;

        AVAssetTrack *audioTrack = tracks.firstObject;

        MTAudioProcessingTapCallbacks callbacks;
        callbacks.version = kMTAudioProcessingTapCallbacksVersion_0;
        callbacks.clientInfo = handle;
        callbacks.init = tap_Init;
        callbacks.finalize = tap_Finalize;
        callbacks.prepare = tap_Prepare;
        callbacks.unprepare = tap_Unprepare;
        callbacks.process = tap_Process;

        MTAudioProcessingTapRef tap = NULL;
        OSStatus status = MTAudioProcessingTapCreate(kCFAllocatorDefault,
                                                      &callbacks,
                                                      kMTAudioProcessingTapCreationFlag_PostEffects,
                                                      &tap);
        if (status != noErr || !tap) return;

        AVMutableAudioMixInputParameters *params =
            [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:audioTrack];
        params.audioTapProcessor = tap;

        AVMutableAudioMix *audioMix = [AVMutableAudioMix audioMix];
        audioMix.inputParameters = @[params];

        CFRelease(tap);

        dispatch_async(dispatch_get_main_queue(), ^{
            playerItem.audioMix = audioMix;
        });
    }];
}

- (void)removeTapFromPlayerItem:(AVPlayerItem *)playerItem {
    playerItem.audioMix = nil;
}

- (void)setVisualizerEnabled:(BOOL)enabled {
    _visualizerEnabled = enabled;
    sVizEnabledGlobal = enabled ? 1 : 0;
    TapContext *ctx = sActiveContext;
    if (ctx) {
        __atomic_store_n(&ctx->vizEnabled, enabled ? 1 : 0, __ATOMIC_RELEASE);
    }
}

- (int)currentSampleRate {
    TapContext *ctx = sActiveContext;
    return ctx ? ctx->sampleRate : 44100;
}

- (nullable NSData *)latestWaveformBytes {
    TapContext *ctx = sActiveContext;
    if (!ctx) return nil;
    if (!__atomic_exchange_n(&ctx->vizWaveformReady, 0, __ATOMIC_ACQ_REL)) {
        return nil;
    }
    return [NSData dataWithBytes:ctx->vizWaveform length:VIZ_CAPTURE_SIZE];
}

- (nullable NSData *)latestFftBytes {
    TapContext *ctx = sActiveContext;
    if (!ctx) return nil;
    if (!__atomic_exchange_n(&ctx->vizFftReady, 0, __ATOMIC_ACQ_REL)) {
        return nil;
    }
    return [NSData dataWithBytes:ctx->vizFft length:VIZ_CAPTURE_SIZE];
}

// PCM float data for projectM (stereo interleaved)
- (nullable NSData *)latestPcmFloat {
    TapContext *ctx = sActiveContext;
    if (!ctx) return nil;
    // Return mono float data from the last waveform capture (VIZ_CAPTURE_SIZE floats)
    if (!ctx->vizWaveformReady) return nil;
    return [NSData dataWithBytes:ctx->fftInput length:VIZ_CAPTURE_SIZE * sizeof(float)];
}

@end
