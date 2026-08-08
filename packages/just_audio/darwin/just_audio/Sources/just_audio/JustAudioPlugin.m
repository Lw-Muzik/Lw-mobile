#import "./include/just_audio/JustAudioPlugin.h"
#import "./include/just_audio/AudioPlayer.h"
#import "./include/just_audio/VideoOutput.h"
#import <AVFoundation/AVFoundation.h>
#include <TargetConditionals.h>

@implementation JustAudioPlugin {
    NSObject<FlutterPluginRegistrar>* _registrar;
    NSMutableDictionary<NSString *, AudioPlayer *> *_players;
    /// Created only for players something has asked to see, which is few of them.
    NSMutableDictionary<NSString *, VideoOutput *> *_videoOutputs;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
        methodChannelWithName:@"com.ryanheise.just_audio.methods"
              binaryMessenger:[registrar messenger]];
    JustAudioPlugin* instance = [[JustAudioPlugin alloc] initWithRegistrar:registrar];
    [registrar addMethodCallDelegate:instance channel:channel];
    // Video rides on its own channel rather than extending the one above: the
    // Dart side of that one is a published platform interface this app consumes
    // rather than owns, and keeping them separate means upstream can be updated
    // without this work having to be re-merged each time.
    FlutterMethodChannel* videoChannel = [FlutterMethodChannel
        methodChannelWithName:@"com.ryanheise.just_audio.video"
              binaryMessenger:[registrar messenger]];
    [registrar addMethodCallDelegate:instance channel:videoChannel];
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    _registrar = registrar;
    _players = [[NSMutableDictionary alloc] init];
    _videoOutputs = [[NSMutableDictionary alloc] init];
    return self;
}

/// The video output for @c playerId, created on first use, or nil if that
/// player has gone away. Losing the race between a screen and the player it
/// belongs to should leave the caller without a texture, not with an exception.
- (VideoOutput *)videoOutputFor:(NSString *)playerId {
    VideoOutput *output = _videoOutputs[playerId];
    if (output != nil) return output;
    AudioPlayer *player = _players[playerId];
    if (player == nil) return nil;
    output = [[VideoOutput alloc] initWithRegistrar:_registrar
                                           playerId:playerId
                                             player:player.player];
    _videoOutputs[playerId] = output;
    return output;
}

- (void)disposeVideoOutputFor:(NSString *)playerId {
    VideoOutput *output = _videoOutputs[playerId];
    if (output == nil) return;
    [output dispose];
    [_videoOutputs removeObjectForKey:playerId];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    //NSLog(@"plugin method: %@", call.method);
    if ([@"init" isEqualToString:call.method]) {
        NSDictionary *request = (NSDictionary *)call.arguments;
        NSString *playerId = (NSString *)request[@"id"];
        NSDictionary *loadConfiguration = (NSDictionary *)request[@"audioLoadConfiguration"];
        BOOL useLazyPreparation = [((NSNumber *)request[@"useLazyPreparation"]) boolValue];
        if ([_players objectForKey:playerId] != nil) {
            FlutterError *flutterError = [FlutterError errorWithCode:@"error" message:@"Platform player already exists" details:nil];
            result(flutterError);
        } else {
            AudioPlayer* player = [[AudioPlayer alloc] initWithRegistrar:_registrar playerId:playerId loadConfiguration:loadConfiguration useLazyPreparation:useLazyPreparation];
            [_players setValue:player forKey:playerId];
            result(nil);
        }
    } else if ([@"disposePlayer" isEqualToString:call.method]) {
        NSDictionary *request = (NSDictionary *)call.arguments;
        NSString *playerId = request[@"id"];
        // Before the player: the output observes it, and an observer outliving
        // its subject is a crash on the next teardown.
        [self disposeVideoOutputFor:playerId];
        [_players[playerId] dispose:NO];
        [_players setValue:nil forKey:playerId];
        result(@{});
    } else if ([@"disposeAllPlayers" isEqualToString:call.method]) {
        for (NSString *playerId in _videoOutputs) {
            [_videoOutputs[playerId] dispose];
        }
        [_videoOutputs removeAllObjects];
        for (NSString *playerId in _players) {
            [_players[playerId] dispose:NO];
        }
        [_players removeAllObjects];
        result(@{});
    } else if ([@"attachVideo" isEqualToString:call.method]) {
        NSString *playerId = ((NSDictionary *)call.arguments)[@"id"];
        VideoOutput *output = [self videoOutputFor:playerId];
        result(output == nil ? nil : @([output attach]));
    } else if ([@"detachVideo" isEqualToString:call.method]) {
        NSString *playerId = ((NSDictionary *)call.arguments)[@"id"];
        [_videoOutputs[playerId] detach];
        result(nil);
    } else if ([@"selectVideoQuality" isEqualToString:call.method]) {
        NSDictionary *request = (NSDictionary *)call.arguments;
        NSNumber *index = request[@"index"];
        [[self videoOutputFor:request[@"id"]] selectQualityAtIndex:index != nil ? index.integerValue : -1];
        result(nil);
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)dealloc {
    for (NSString *playerId in _videoOutputs) {
        [_videoOutputs[playerId] dispose];
    }
    [_videoOutputs removeAllObjects];
    for (NSString *playerId in _players) {
        [_players[playerId] dispose:YES];
    }
    [_players removeAllObjects];
}

@end
