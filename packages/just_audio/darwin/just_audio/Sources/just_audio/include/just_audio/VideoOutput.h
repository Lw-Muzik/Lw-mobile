#import <AVFoundation/AVFoundation.h>
#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif

/**
 * The video half of a player that was only ever asked for audio.
 *
 * AVPlayer has always been able to produce video frames; nothing was ever asked
 * to collect them. This attaches an AVPlayerItemVideoOutput and pumps the frames
 * into a Flutter texture, so the picture appears while the sound keeps taking
 * the path it already took — through the MTAudioProcessingTap that carries this
 * app's DSP. Video inherits the equaliser, the queue and the background session
 * because it is the same player, not a second one placed beside it.
 *
 * Detaching stops frame production rather than merely hiding it: a phone with
 * its screen off has no use for decoded frames.
 */
@interface VideoOutput : NSObject<FlutterTexture>

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar
                         playerId:(NSString *)playerId
                           player:(AVQueuePlayer *)player;

/** Creates the texture and starts collecting frames. Returns its id. */
- (int64_t)attach;

/** Releases the texture and stops collecting frames. */
- (void)detach;

/** Pins the rendition at @c index in the last broadcast list; -1 is adaptive. */
- (void)selectQualityAtIndex:(NSInteger)index;

- (void)dispose;

@end
