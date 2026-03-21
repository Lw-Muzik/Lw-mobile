import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:id3tag/id3tag.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'index.dart';

class HypeAudioHandler extends BaseAudioHandler {
  /// Streaming-optimized load configuration:
  /// - Android: small initial buffer (1.5s) for fast start, large max buffer
  ///   (2 min) for resilience on flaky connections, quick rebuffer (3s)
  /// - iOS: auto-wait to minimize stalling, 60s forward buffer
  static final _streamingLoadConfig = AudioLoadConfiguration(
    androidLoadControl: const AndroidLoadControl(
      minBufferDuration: Duration(seconds: 30),
      maxBufferDuration: Duration(seconds: 120),
      bufferForPlaybackDuration: Duration(milliseconds: 1500),
      bufferForPlaybackAfterRebufferDuration: Duration(seconds: 3),
      prioritizeTimeOverSizeThresholds: true,
    ),
    darwinLoadControl: const DarwinLoadControl(
      automaticallyWaitsToMinimizeStalling: true,
      preferredForwardBufferDuration: Duration(seconds: 60),
    ),
  );

  final AudioPlayer _playerA = AudioPlayer(
    audioLoadConfiguration: _streamingLoadConfig,
  );
  final AudioPlayer _playerB = AudioPlayer(
    audioLoadConfiguration: _streamingLoadConfig,
  );
  late AudioPlayer _activePlayer;
  late AudioPlayer _inactivePlayer;

  StreamSubscription<PlaybackEvent>? _playbackSub;
  bool _isCrossfading = false;

  /// The primary player used for playback controls (play/pause/stop/seek).
  AudioPlayer get player => _activePlayer;

  /// The player that has the latest track loaded.
  /// During crossfade this returns the incoming player (new track).
  /// Outside crossfade this is the same as [player].
  AudioPlayer get currentTrackPlayer =>
      _isCrossfading ? _inactivePlayer : _activePlayer;

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

  @override
  Future<void> play() => _activePlayer.play();

  @override
  Future<void> pause() => _activePlayer.pause();

  @override
  Future<void> stop() async {
    await _activePlayer.stop();
    await _inactivePlayer.stop();
  }

  @override
  Future<void> seek(Duration position) => _activePlayer.seek(position);

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
    final targetVolume = replayGain
        ? await computeReplayGainVolume(nextSong.data)
        : 1.0;

    await _inactivePlayer.setAudioSource(nextSource);
    _inactivePlayer.setVolume(0.0);
    _inactivePlayer.play();

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
      final progress = i / steps;
      _activePlayer.setVolume(currentVolume * (1.0 - progress));
      _inactivePlayer.setVolume(targetVolume * progress);
    }

    // Stop old active player, swap
    await _activePlayer.stop();
    _activePlayer.setVolume(1.0);

    final temp = _activePlayer;
    _activePlayer = _inactivePlayer;
    _inactivePlayer = temp;

    _isCrossfading = false;
    _bindPlaybackState();
    onPlayerSwapped?.call();
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
