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

/** Whether this output currently holds a texture. */
- (BOOL)isAttached;

// ---- Picture-in-picture ----
//
// AVKit drives picture-in-picture from an @c AVPlayerLayer, and this app draws
// video into a Flutter texture instead — so there is no layer for it to attach
// to unless one is made. That is what this does: a layer bound to the same
// player, placed behind the Flutter view where it is occluded but present, for
// AVKit to hand to the system window. The texture keeps drawing the picture the
// user sees inline; the layer exists solely so iOS has something to float.

/** Whether this device offers picture-in-picture at all. */
- (BOOL)pipSupported;

/** Floats the video now. Returns whether the request was made. */
- (BOOL)pipStart;

/**
 * Whether leaving the app should float the video automatically.
 *
 * iOS 14.2 and later only — earlier versions offer no equivalent, and the
 * button remains the way in.
 */
- (void)pipSetAutoEnter:(BOOL)on;

/** Reports entering and leaving the floating window. */
- (void)setPipChannel:(FlutterMethodChannel *)channel;

- (void)dispose;

@end
