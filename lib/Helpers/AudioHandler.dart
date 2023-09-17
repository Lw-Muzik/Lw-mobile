import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class HypeMuzikiAudioHandler extends BaseAudioHandler with SeekHandler {
  AudioPlayer player = AudioPlayer();
  // MediaItem? mediaItem;
  // Initialise our audio handler.
  HypeMuzikiAudioHandler() {
    // So that our clients (the Flutter UI and the system notification) know
    // what state to display, here we set up our audio handler to broadcast all
    // playback state changes as they happen via playbackState...
    player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    // // ... and also the current media item via mediaItem.
    // mediaItem.add(_item);

    // // Load the player.
    // player
    //     .setAudioSource(AudioSource.uri(Uri.parse(_item.id)));
  }
  void setAudioSource(AudioSource source) {
    player.setAudioSource(source);
  }

  void setShuffleModeEnabled(bool enable) {
    player.setShuffleModeEnabled(enable);
  }

  void setLoopMode(LoopMode mode) {
    player.setLoopMode(mode);
  }

  Stream<PlayerState> get playerStateStream => player.playerStateStream;
  bool get playing => player.playing;
  Stream<LoopMode> get loopModeStream => player.loopModeStream;
  Stream<bool> get playingStream => player.playingStream;
  Stream<bool> get shuffleModeEnabledStream => player.shuffleModeEnabledStream;
  Stream<Duration> get positionStream => player.positionStream;
  Stream<Duration> get bufferedPositionStream => player.bufferedPositionStream;
  Stream<Duration?> get durationStream => player.durationStream;
  int get sessionId => player.androidAudioSessionId ?? 0;
  Stream<int?> get sessionIdStream => player.androidAudioSessionIdStream;
  // The most common callbacks:
  @override
  Future<void> play() async {
    // All 'play' requests from all origins route to here. Implement this
    // callback to start playing audio appropriate to your app. e.g. music.
    player.play();
  }

  @override
  Future<void> pause() async {
    player.pause();
  }

  @override
  Future<void> stop() async {
    player.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    player.seek(position);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    player.stop();
  }

  // @override
  // Future<void> click([Media]) async {}

  /// Transform a just_audio event into an audio_service state.
  ///
  /// This method is used from the constructor. Every event received from the
  /// just_audio player will be transformed into an audio_service state so that
  /// it can be broadcast to audio_service clients.
  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.rewind,
        if (player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.fastForward,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[player.processingState]!,
      playing: player.playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: event.currentIndex,
    );
  }
}
