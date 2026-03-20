#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HypeAudioTap : NSObject

+ (instancetype)shared;

/// Set the DSP engine handle (called from AppDelegate after DSPManager init)
- (void)setDspHandle:(void *)handle;

/// Install DSP processing + visualization tap on an AVPlayerItem.
- (void)installTapOnPlayerItem:(AVPlayerItem *)playerItem;

/// Remove tap from a player item
- (void)removeTapFromPlayerItem:(AVPlayerItem *)playerItem;

/// Visualization control
@property (nonatomic, assign) BOOL visualizerEnabled;

/// Latest visualization data as raw bytes (matches Android Visualizer format)
/// Waveform: VIZ_CAPTURE_SIZE unsigned bytes [0-255], silence = 128
/// FFT: VIZ_CAPTURE_SIZE bytes, interleaved [real, imag] pairs
- (nullable NSData *)latestWaveformBytes;
- (nullable NSData *)latestFftBytes;
- (int)currentSampleRate;

/// Raw PCM float data for projectM feeding
- (nullable NSData *)latestPcmFloat;

@end

NS_ASSUME_NONNULL_END
