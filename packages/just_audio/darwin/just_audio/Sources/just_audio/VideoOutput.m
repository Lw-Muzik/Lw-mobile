#import "./include/just_audio/VideoOutput.h"
#import "./include/just_audio/BetterEventChannel.h"
#include <TargetConditionals.h>

/// KVO contexts, so observations meant for this object are never confused with
/// a superclass's.
static void *kItemContext = &kItemContext;
static void *kSizeContext = &kSizeContext;

@implementation VideoOutput {
    NSObject<FlutterTextureRegistry> *_textures;
    BetterEventChannel *_eventChannel;
    AVQueuePlayer *_player;

    AVPlayerItemVideoOutput *_output;
    AVPlayerItem *_observedItem;
    int64_t _textureId;
    BOOL _attached;

#if TARGET_OS_OSX
    dispatch_source_t _timer;
#else
    CADisplayLink *_displayLink;
#endif

    /// The renditions last offered to Dart, and which one is pinned.
    NSArray<AVAssetVariant *> *_variants;
    NSInteger _selected;
    CGSize _lastSize;
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar
                         playerId:(NSString *)playerId
                           player:(AVQueuePlayer *)player {
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    _textures = [registrar textures];
    _player = player;
    _textureId = -1;
    _attached = NO;
    _selected = -1;
    _lastSize = CGSizeZero;
    _variants = @[];
    _eventChannel = [[BetterEventChannel alloc]
        initWithName:[NSString stringWithFormat:@"com.ryanheise.just_audio.video.%@", playerId]
       messenger:[registrar messenger]];
    [_player addObserver:self
              forKeyPath:@"currentItem"
                 options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                 context:kItemContext];
    return self;
}

- (int64_t)attach {
    if (_attached) return _textureId;
    _attached = YES;

    // BGRA rather than a planar format: Flutter's texture path uploads BGRA
    // without a conversion step, and the conversion is the expensive part.
    NSDictionary *attributes = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey : @{},
    };
    _output = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:attributes];
    [self attachOutputToCurrentItem];

    _textureId = [_textures registerTexture:self];
    [self startPump];
    // Undo the resolution floor that detaching imposed — see -detach.
    [self selectQualityAtIndex:_selected];
    [self broadcast];
    return _textureId;
}

- (void)detach {
    if (!_attached) return;
    _attached = NO;
    [self stopPump];
    [self detachOutputFromCurrentItem];
    _output = nil;
    if (_textureId >= 0) {
        [_textures unregisterTexture:_textureId];
        _textureId = -1;
    }
    // AVPlayer has no way to turn a video track off the way ExoPlayer does, so
    // this is the nearest honest equivalent: ask for the smallest picture there
    // is, and let variant selection drop to the cheapest rendition. Frames are
    // still being fetched — fewer bytes of them, but not none. A phone with its
    // screen off pays less for a video nobody is watching, not nothing.
    AVPlayerItem *item = _player.currentItem;
    if (item != nil) {
        item.preferredMaximumResolution = CGSizeMake(16, 16);
    }
    [self broadcast];
}

#pragma mark - Frame pump

/**
 * Frames are pulled on the display's own cadence rather than pushed.
 *
 * AVPlayerItemVideoOutput has no callback for "a frame is ready"; it answers
 * whether one exists for a given time. Asking once per displayed frame is both
 * the cheapest correct rate and the one that keeps video in step with the
 * screen rather than with a timer that drifts against it.
 */
- (void)startPump {
#if TARGET_OS_OSX
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, NSEC_PER_SEC / 60, NSEC_PER_SEC / 600);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_timer, ^{ [weakSelf onFrameTick]; });
    dispatch_resume(_timer);
#else
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onFrameTick)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
#endif
}

- (void)stopPump {
#if TARGET_OS_OSX
    if (_timer) {
        dispatch_source_cancel(_timer);
        _timer = nil;
    }
#else
    [_displayLink invalidate];
    _displayLink = nil;
#endif
}

- (void)onFrameTick {
    if (!_attached || _output == nil || _textureId < 0) return;
    CMTime time = [_output itemTimeForHostTime:CACurrentMediaTime()];
    if ([_output hasNewPixelBufferForItemTime:time]) {
        [_textures textureFrameAvailable:_textureId];
    }
}

- (CVPixelBufferRef _Nullable)copyPixelBuffer {
    if (_output == nil) return NULL;
    CMTime time = [_output itemTimeForHostTime:CACurrentMediaTime()];
    if (![_output hasNewPixelBufferForItemTime:time]) return NULL;
    return [_output copyPixelBufferForItemTime:time itemTimeForDisplay:NULL];
}

#pragma mark - Item tracking

- (void)attachOutputToCurrentItem {
    AVPlayerItem *item = _player.currentItem;
    if (item == nil || _output == nil) return;
    // Adding the same output twice throws; the guard is not defensive padding.
    if (![item.outputs containsObject:_output]) {
        [item addOutput:_output];
    }
}

- (void)detachOutputFromCurrentItem {
    AVPlayerItem *item = _player.currentItem;
    if (item != nil && _output != nil && [item.outputs containsObject:_output]) {
        [item removeOutput:_output];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (context == kItemContext) {
        if (_observedItem != nil) {
            [_observedItem removeObserver:self forKeyPath:@"presentationSize" context:kSizeContext];
            _observedItem = nil;
        }
        // The size belongs to the item that is leaving. Keeping it would shape
        // the next track's surface like the last one's video.
        _lastSize = CGSizeZero;
        _variants = @[];
        _selected = -1;

        AVPlayerItem *item = _player.currentItem;
        if (item != nil) {
            _observedItem = item;
            [item addObserver:self
                   forKeyPath:@"presentationSize"
                      options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                      context:kSizeContext];
            if (_attached) [self attachOutputToCurrentItem];
            [self loadVariantsForItem:item];
        }
        [self broadcast];
    } else if (context == kSizeContext) {
        _lastSize = _player.currentItem.presentationSize;
        [self broadcast];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

/**
 * Reads the renditions an HLS asset offers.
 *
 * Progressive files have exactly one, which is not a menu, so nothing is
 * offered for them. DASH never reaches here: AVPlayer cannot open it, and the
 * caller says so rather than handing it a manifest it will fail on.
 */
- (void)loadVariantsForItem:(AVPlayerItem *)item {
    if (@available(iOS 15.0, macOS 12.0, *)) {
        AVAsset *asset = item.asset;
        __weak typeof(self) weakSelf = self;
        [asset loadValuesAsynchronouslyForKeys:@[ @"variants" ] completionHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) strongSelf = weakSelf;
                if (strongSelf == nil || strongSelf->_player.currentItem != item) return;
                NSError *error = nil;
                if ([asset statusOfValueForKey:@"variants" error:&error] != AVKeyValueStatusLoaded) return;
                NSArray<AVAssetVariant *> *variants = asset.variants;
                // Largest first: a quality menu reads downwards from the best.
                strongSelf->_variants = [variants sortedArrayUsingComparator:^NSComparisonResult(AVAssetVariant *a, AVAssetVariant *b) {
                    CGSize sa = a.videoAttributes.presentationSize;
                    CGSize sb = b.videoAttributes.presentationSize;
                    return [@(sb.width * sb.height) compare:@(sa.width * sa.height)];
                }];
                [strongSelf broadcast];
            });
        }];
    }
}

#pragma mark - Quality

/**
 * Pins a rendition by capping the resolution AVPlayer is allowed to choose.
 *
 * AVPlayer offers no way to name a variant outright — the constraint is the
 * only lever. Capping to the chosen size leaves it free to drop lower when the
 * network cannot sustain that, which is the honest behaviour: the alternative
 * to a lower rendition is not a higher one, it is a stall.
 */
- (void)selectQualityAtIndex:(NSInteger)index {
    AVPlayerItem *item = _player.currentItem;
    if (item == nil) return;

    if (index < 0 || index >= (NSInteger)_variants.count) {
        _selected = -1;
        item.preferredMaximumResolution = CGSizeZero;
        item.preferredPeakBitRate = 0;
    } else {
        _selected = index;
        if (@available(iOS 15.0, macOS 12.0, *)) {
            AVAssetVariant *variant = _variants[index];
            item.preferredMaximumResolution = variant.videoAttributes.presentationSize;
            NSNumber *peak = variant.peakBitRate;
            item.preferredPeakBitRate = peak != nil ? peak.doubleValue : 0;
        }
    }
    [self broadcast];
}

#pragma mark - Events

- (void)broadcast {
    NSMutableArray *renditions = [NSMutableArray array];
    if (@available(iOS 15.0, macOS 12.0, *)) {
        for (AVAssetVariant *variant in _variants) {
            CGSize size = variant.videoAttributes.presentationSize;
            if (size.width <= 0 || size.height <= 0) continue;
            NSNumber *rate = variant.videoAttributes.nominalFrameRate;
            NSNumber *peak = variant.peakBitRate;
            [renditions addObject:@{
                @"width" : @((int)size.width),
                @"height" : @((int)size.height),
                @"bitrate" : @(peak != nil ? peak.intValue : 0),
                @"frameRate" : @(rate != nil ? rate.doubleValue : 0.0),
                @"codecs" : @"",
            }];
        }
    }
    [_eventChannel sendEvent:@{
        @"width" : @((int)_lastSize.width),
        @"height" : @((int)_lastSize.height),
        @"pixelAspectRatio" : @(1.0),
        @"renditions" : renditions,
        @"selected" : @(_selected),
    }];
}

- (void)dispose {
    [self detach];
    if (_observedItem != nil) {
        [_observedItem removeObserver:self forKeyPath:@"presentationSize" context:kSizeContext];
        _observedItem = nil;
    }
    [_player removeObserver:self forKeyPath:@"currentItem" context:kItemContext];
    [_eventChannel dispose];
    _player = nil;
}

@end
