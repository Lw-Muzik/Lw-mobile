/// Does a resolved YouTube stream actually play **on this phone**?
///
/// Everything else in this repo tests Dart. This runs on the device, against
/// the real ExoPlayer, with the same `AudioPlayer` configuration the app uses —
/// which is the only place the answer lives. A URL that serves bytes to `curl`
/// and still won't play is a player-side problem, and nothing short of the
/// player can tell you which one.
///
/// Run it at the device:
///
/// ```
/// flutter test integration_test/yt_playback_device_test.dart -d <device>
/// ```
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:eq_app/services/ytmusic/yt_models.dart';
import 'package:eq_app/services/ytmusic/yt_worker.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The app's own load configuration, copied from `HypeAudioHandler` so this
  /// tests what ships rather than a default player.
  final loadConfig = AudioLoadConfiguration(
    androidLoadControl: const AndroidLoadControl(
      minBufferDuration: Duration(seconds: 30),
      maxBufferDuration: Duration(seconds: 30),
      bufferForPlaybackDuration: Duration(seconds: 2),
      bufferForPlaybackAfterRebufferDuration: Duration(seconds: 4),
      prioritizeTimeOverSizeThresholds: true,
    ),
  );

  Future<StreamTarget> resolveOne() async {
    final shelves = await YtWorker.instance.run<List<ExploreShelf>>(
      YtOp.search,
      {'query': 'Burna Boy Last Last', 'params': SearchFilter.songs.params},
    );
    final song = shelves.expand((s) => s.items).firstWhere((i) => i.isPlayable);
    return YtWorker.instance
        .run<StreamTarget>(YtOp.resolveAudio, {'videoId': song.id});
  }

  /// Waits for the player to actually produce a moving position.
  ///
  /// `play()` returning proves nothing — it resolves as soon as the command is
  /// sent. Real playback is the position advancing past zero.
  Future<Duration> playAndMeasure(AudioPlayer player) async {
    unawaited(player.play());
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (player.position > Duration.zero) return player.position;
    }
    return Duration.zero;
  }

  testWidgets('plays with headers, no proxy — the shipped configuration',
      (tester) async {
    final target = await resolveOne();
    final player = AudioPlayer(
      audioLoadConfiguration: loadConfig,
      useProxyForRequestHeaders: false,
    );
    addTearDown(player.dispose);

    Object? failure;
    try {
      await player.setAudioSource(
        AudioSource.uri(Uri.parse(target.url), headers: target.headers),
      );
    } catch (e) {
      failure = e;
    }
    // ignore: avoid_print
    print('[headers,no-proxy] setAudioSource error: $failure');
    expect(failure, isNull, reason: 'ExoPlayer refused the source: $failure');

    // ignore: avoid_print
    print('[headers,no-proxy] duration: ${player.duration}');
    final position = await playAndMeasure(player);
    // ignore: avoid_print
    print('[headers,no-proxy] position after play: $position');
    expect(position, greaterThan(Duration.zero),
        reason: 'the source loaded but produced no audio');
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('plays with no headers at all', (tester) async {
    final target = await resolveOne();
    final player = AudioPlayer(audioLoadConfiguration: loadConfig);
    addTearDown(player.dispose);

    Object? failure;
    try {
      await player.setAudioSource(AudioSource.uri(Uri.parse(target.url)));
    } catch (e) {
      failure = e;
    }
    // ignore: avoid_print
    print('[no-headers] setAudioSource error: $failure');
    // ignore: avoid_print
    print('[no-headers] duration: ${player.duration}');
    final position = await playAndMeasure(player);
    // ignore: avoid_print
    print('[no-headers] position after play: $position');
    expect(failure, isNull);
    expect(position, greaterThan(Duration.zero));
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('plays through a multi-source queue, as gapless mode builds it',
      (tester) async {
    final target = await resolveOne();
    final player = AudioPlayer(
      audioLoadConfiguration: loadConfig,
      useProxyForRequestHeaders: false,
    );
    addTearDown(player.dispose);

    Object? failure;
    try {
      await player.setAudioSources([
        AudioSource.uri(Uri.parse(target.url), headers: target.headers),
      ], initialIndex: 0);
    } catch (e) {
      failure = e;
    }
    // ignore: avoid_print
    print('[queue] setAudioSources error: $failure');
    final position = await playAndMeasure(player);
    // ignore: avoid_print
    print('[queue] position after play: $position');
    expect(failure, isNull);
    expect(position, greaterThan(Duration.zero));
  }, timeout: const Timeout(Duration(seconds: 120)));
}
