import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio/video.dart';
import 'package:id3tag/id3tag.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'index.dart';

class HypeAudioHandler extends BaseAudioHandler {
  /// Data-conscious streaming configuration (Spotify-style drip-feed):
  /// - Android: drip-feed buffer (min == max at 30s) prevents bursty over-download.
  ///   ExoPlayer downloads in ~1MB chunks; 30s is enough for smooth playback
  ///   while keeping data usage proportional to actual listening time.
  ///   Fast start at 2s, quick rebuffer at 4s.
  /// - iOS: auto-wait to minimize stalling, 30s forward buffer,
  ///   preferredPeakBitRate limits bandwidth on cellular.
  static final _streamingLoadConfig = AudioLoadConfiguration(
    androidLoadControl: const AndroidLoadControl(
      minBufferDuration: Duration(seconds: 30),
      maxBufferDuration: Duration(seconds: 30),
      bufferForPlaybackDuration: Duration(seconds: 2),
      bufferForPlaybackAfterRebufferDuration: Duration(seconds: 4),
      prioritizeTimeOverSizeThresholds: true,
    ),
    darwinLoadControl: const DarwinLoadControl(
      automaticallyWaitsToMinimizeStalling: true,
      preferredForwardBufferDuration: Duration(seconds: 30),
    ),
  );

  // `useProxyForRequestHeaders: false` — send request headers natively rather
  // than through just_audio's local HTTP proxy.
  //
  // By default, *any* source carrying headers is rewritten to
  // `http://127.0.0.1:<port>/<original path and query>` and served by a
  // cleartext proxy inside the app. That is a poor fit for YouTube: a
  // googlevideo URL carries a thousand-character query string, and the proxy
  // sits between the player and the CDN for every Range request and every seek.
  // With this off, ExoPlayer uses `setDefaultRequestProperties` and AVPlayer
  // uses `AVURLAssetHTTPHeaderFieldsKey`, so the player talks to the CDN
  // directly — no extra hop, native Range and seek, and no dependence on
  // cleartext traffic being permitted.
  final AudioPlayer _playerA = AudioPlayer(
    audioLoadConfiguration: _streamingLoadConfig,
    useProxyForRequestHeaders: false,
  );
  final AudioPlayer _playerB = AudioPlayer(
    audioLoadConfiguration: _streamingLoadConfig,
    useProxyForRequestHeaders: false,
  );
  late AudioPlayer _activePlayer;
  late AudioPlayer _inactivePlayer;

  StreamSubscription<PlaybackEvent>? _playbackSub;
  bool _isCrossfading = false;

  /// Set while a crossfade is in flight; completed when it settles (normal
  /// completion, abort, or failure). Lets control paths await a fast settle.
  Completer<void>? _fadeDone;
  bool _cancelCrossfade = false;

  /// The primary player used for playback controls (play/pause/stop/seek).
  AudioPlayer get player => _activePlayer;

  /// Video surfaces, one per player, created the first time one is asked for.
  ///
  /// Keyed by player rather than held as a single field because there are two
  /// of them for crossfading, and a surface belongs to the engine that draws
  /// into it. Videos never crossfade — `AppController` refuses the fade when
  /// either side is one — so in practice only the active player ever grows a
  /// surface, but tying the two together explicitly is what makes that true by
  /// construction rather than by luck.
  final Map<AudioPlayer, VideoOutput> _videoOutputs = {};

  /// The video surface of whichever player is currently audible.
  VideoOutput get video => videoOutputFor(currentTrackPlayer);

  VideoOutput videoOutputFor(AudioPlayer player) =>
      _videoOutputs.putIfAbsent(player, () => VideoOutput(player));

  /// The player that has the latest track loaded.
  /// During crossfade this returns the incoming player (new track).
  /// Outside crossfade this is the same as [player].
  AudioPlayer get currentTrackPlayer =>
      _isCrossfading ? _inactivePlayer : _activePlayer;

  /// Repeat mode, held here rather than on one player.
  ///
  /// There are two players so tracks can crossfade, and a crossfade ends by
  /// swapping which one is active. Setting the mode on `player` alone therefore
  /// survived exactly until the first crossfade, after which the incoming
  /// player — which had never been told — silently reverted to no repeat. Both
  /// are set, always, so the swap cannot lose it.
  LoopMode _loopMode = LoopMode.off;

  LoopMode get loopMode => _loopMode;

  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;
    await Future.wait([
      _playerA.setLoopMode(mode),
      _playerB.setLoopMode(mode),
    ]);
  }

  VoidCallback? onSkipToNext;
  VoidCallback? onSkipToPrevious;

  /// Fired right after the new track starts playing on the incoming player
  /// (before the fade begins) so the UI can bind to [currentTrackPlayer].
  VoidCallback? onCrossfadeStarted;

  /// Fired after a crossfade completes so AppController can re-bind streams.
  VoidCallback? onPlayerSwapped;

  HypeAudioHandler() {
    _activePlayer = _playerA;
    _inactivePlayer = _playerB;
    _bindPlaybackState();
  }

  void _bindPlaybackState() {
    _playbackSub?.cancel();
    _playbackSub = _activePlayer.playbackEventStream.listen((event) {
      playbackState.add(_transformEvent(event));
    });
  }

  // Controls route to [currentTrackPlayer]: during a crossfade the audible
  // track lives on the incoming player — acting on _activePlayer (outgoing)
  // would target a player the fade loop is about to stop.
  @override
  Future<void> play() => currentTrackPlayer.play();

  @override
  Future<void> pause() => currentTrackPlayer.pause();

  @override
  Future<void> stop() async {
    await abortCrossfade();
    await _activePlayer.stop();
    await _inactivePlayer.stop();
  }

  @override
  Future<void> seek(Duration position) => currentTrackPlayer.seek(position);

  /// Fast-settle any in-flight crossfade: the fade loop breaks at its next
  /// step (≤ fadeDuration/20), the swap completes immediately, and callers can
  /// then safely act on [player]. No-op when no crossfade is running.
  Future<void> abortCrossfade() async {
    final done = _fadeDone;
    if (done == null) return;
    _cancelCrossfade = true;
    await done.future;
  }

  @override
  Future<void> skipToNext() async {
    onSkipToNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    onSkipToPrevious?.call();
  }

  void setCurrentMediaItem(MediaItem item) {
    mediaItem.add(item);
  }

  /// Crossfade from current track to next.
  /// Loads [nextSource] on the inactive player, fades volumes, then swaps.
  Future<void> beginCrossfade(
    AudioSource nextSource,
    SongModel nextSong,
    Duration fadeDuration, {
    bool replayGain = false,
  }) async {
    if (_fadeDone != null) return; // one crossfade at a time

    final fadeDone = Completer<void>();
    _fadeDone = fadeDone;
    _cancelCrossfade = false;
    final origVolume = _activePlayer.volume;
    var incomingStarted = false;

    try {
      final targetVolume = replayGain
          ? await computeReplayGainVolume(nextSong.data)
          : 1.0;

      await _inactivePlayer.setAudioSource(nextSource);
      _inactivePlayer.setVolume(0.0);
      _inactivePlayer.play();
      incomingStarted = true;

      // Update media item for the next track
      final image = await fetchArtworkUrl(nextSong.data, nextSong.id);
      final item = MediaItem(
        id: nextSong.data,
        album: nextSong.album,
        title: nextSong.title,
        artist: nextSong.artist,
        duration: Duration(milliseconds: nextSong.duration ?? 0),
        artUri: Uri.file(image),
      );

      setCurrentMediaItem(item);

      // Signal that the new track is now playing on _inactivePlayer.
      // currentTrackPlayer will return _inactivePlayer while _isCrossfading.
      _isCrossfading = true;
      onCrossfadeStarted?.call();

      const steps = 20;
      final stepDuration = Duration(
        milliseconds: fadeDuration.inMilliseconds ~/ steps,
      );
      final currentVolume = _activePlayer.volume;

      for (var i = 1; i <= steps; i++) {
        await Future.delayed(stepDuration);
        // Abort requested (user skipped/paused/loaded a track): jump straight
        // to the end state instead of finishing the audible fade.
        if (_cancelCrossfade) break;
        final progress = i / steps;
        _activePlayer.setVolume(currentVolume * (1.0 - progress));
        _inactivePlayer.setVolume(targetVolume * progress);
      }

      // Stop old active player, snap incoming to target, swap
      _inactivePlayer.setVolume(targetVolume);
      await _activePlayer.stop();
      _activePlayer.setVolume(1.0);

      final temp = _activePlayer;
      _activePlayer = _inactivePlayer;
      _inactivePlayer = temp;

      _isCrossfading = false;
      _bindPlaybackState();
      onPlayerSwapped?.call();
    } catch (e) {
      // Failed before the swap (e.g. dead cloud URL in setAudioSource, or
      // artwork I/O). Restore the outgoing player and silence the incoming
      // one so it can't keep playing invisibly; rethrow so the caller can
      // roll back its track state.
      _isCrossfading = false;
      _activePlayer.setVolume(origVolume);
      if (incomingStarted) {
        try {
          await _inactivePlayer.stop();
        } catch (_) {}
      }
      rethrow;
    } finally {
      // Whatever happened, the crossfade is settled: unblock abortCrossfade()
      // waiters and clear the guard so future crossfades can run.
      _isCrossfading = false;
      _fadeDone = null;
      fadeDone.complete();
    }
  }

  /// Compute replay gain volume from ID3 tags
  static Future<double> computeReplayGainVolume(String filePath) async {
    try {
      final parser = ID3TagReader.path(filePath);
      final tag = await parser.readTag();
      // Look for TXXX frames with replaygain_track_gain
      final txxxFrames = tag.framesWithName('TXXX');
      for (final frame in txxxFrames) {
        if (frame is TextInformation) {
          final val = frame.value.toLowerCase();
          if (val.contains('replaygain_track_gain')) {
            final gainStr = frame.value
                .replaceAll(RegExp(r'replaygain_track_gain', caseSensitive: false), '')
                .replaceAll(RegExp(r'[^\d.\-+]'), '');
            final dB = double.tryParse(gainStr) ?? 0.0;
            final linear = math.pow(10, dB / 20).toDouble();
            return linear.clamp(0.1, 2.5);
          }
        }
      }
    } catch (_) {
      // If we can't read tags, return default
    }
    return 1.0;
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_activePlayer.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_activePlayer.processingState]!,
      playing: _activePlayer.playing,
      updatePosition: _activePlayer.position,
      bufferedPosition: _activePlayer.bufferedPosition,
      speed: _activePlayer.speed,
      queueIndex: event.currentIndex,
    );
  }
}
