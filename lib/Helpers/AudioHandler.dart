import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:id3tag/id3tag.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'index.dart';

class HypeAudioHandler extends BaseAudioHandler {
  final AudioPlayer _playerA = AudioPlayer();
  final AudioPlayer _playerB = AudioPlayer();
  late AudioPlayer _activePlayer;
  late AudioPlayer _inactivePlayer;

  AudioPlayer get player => _activePlayer;

  VoidCallback? onSkipToNext;
  VoidCallback? onSkipToPrevious;

  HypeAudioHandler() {
    _activePlayer = _playerA;
    _inactivePlayer = _playerB;
    _playerA.playbackEventStream.map(_transformEvent).pipe(playbackState);
  }

  void _rebindPlaybackState() {
    // Pipe the new active player's events
    _activePlayer.playbackEventStream.map(_transformEvent).pipe(playbackState);
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

    final steps = 20;
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

    setCurrentMediaItem(item);
    _rebindPlaybackState();
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
            // Value format: "replaygain_track_gain\x00+3.5 dB" or similar
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
