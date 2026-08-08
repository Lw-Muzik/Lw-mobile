/// Does a music video actually play **on this phone**?
///
/// Video is the harder half: YouTube hands back separate video and audio
/// renditions, and the app combines them into a DASH manifest (see
/// `parse/yt_dash.dart`). Whether ExoPlayer accepts that manifest — and whether
/// googlevideo serves the byte ranges DASH asks for — is only answerable here.
///
/// Played through the app's own player rather than a plugin, which is the point
/// of the exercise: the same [AudioPlayer] that plays the music, given a video
/// surface. What this test proves is not merely that the manifest is valid but
/// that the engine carrying the equaliser, the queue and the background service
/// can carry a picture too.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio/video.dart';

import 'package:eq_app/services/video/video_registry.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';
import 'package:eq_app/services/ytmusic/yt_worker.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<(ExploreItem, StreamTarget)> resolveVideo() async {
    final shelves = await YtWorker.instance.run<List<ExploreShelf>>(
      YtOp.search,
      {'query': 'Burna Boy', 'params': SearchFilter.videos.params},
    );
    final video = shelves
        .expand((s) => s.items)
        .firstWhere((i) => i.kind == ExploreKind.video);
    final target = await YtWorker.instance
        .run<StreamTarget>(YtOp.resolveVideo, {'videoId': video.id});
    return (video, target);
  }

  /// Stages a resolved target the way the app does and loads it into a player
  /// with a video surface attached.
  Future<(AudioPlayer, VideoOutput)> open(
    ExploreItem item,
    StreamTarget target,
  ) async {
    final source = await VideoRegistry.instance.adopt(
      songId: item.id.hashCode.abs(),
      videoId: item.id,
      target: target,
    );
    expect(source, isNotNull, reason: 'the manifest could not be staged');

    final player = AudioPlayer(useProxyForRequestHeaders: false);
    final video = VideoOutput(player);
    addTearDown(() async {
      await video.dispose();
      await player.dispose();
      VideoRegistry.instance.resetForTest();
    });

    await player.setAudioSource(source!.toAudioSource());
    // After the source: the surface is handed to a player that exists, and a
    // video track cannot be selected before there is a manifest describing one.
    final texture = await video.attach();
    expect(texture, isNotNull, reason: 'no platform texture was produced');
    return (player, video);
  }

  Future<Duration> playUntilPast(AudioPlayer player, Duration mark) async {
    unawaited(player.play());
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    var position = Duration.zero;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      position = player.position;
      if (position > mark) break;
    }
    return position;
  }

  testWidgets('a music video plays through the app player', (tester) async {
    final (item, target) = await resolveVideo();
    // ignore: avoid_print
    print('[video] "${item.title}" resolved as ${target.format.name}');

    final (player, video) = await open(item, target);

    // ignore: avoid_print
    print('[video] duration ${player.duration}');
    expect(player.duration, isNotNull);
    expect(player.duration, greaterThan(Duration.zero));

    final position = await playUntilPast(player, Duration.zero);
    // ignore: avoid_print
    print('[video] position after play: $position');
    expect(position, greaterThan(Duration.zero),
        reason: 'the manifest loaded but no frames were produced');

    // The surface having been handed over is not proof that anything was drawn
    // on it. A reported video size is: it comes from the decoder.
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!video.state.hasVideo && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    // ignore: avoid_print
    print('[video] size ${video.state.width}x${video.state.height}, '
        '${video.state.renditions.length} renditions');
    expect(video.state.hasVideo, isTrue,
        reason: 'the decoder never reported a video size');
  }, timeout: const Timeout(Duration(seconds: 180)));

  /// Seeking deep into a video is where large byte-range requests happen — the
  /// thing googlevideo has been observed refusing when they get too big.
  testWidgets('a music video seeks past the first megabyte', (tester) async {
    final (item, target) = await resolveVideo();
    if (target.format != YtStreamFormat.dash) {
      // ignore: avoid_print
      print('[seek] HLS target — nothing to prove about DASH ranges');
      return;
    }
    final (player, _) = await open(item, target);

    await player.play();
    await player.seek(const Duration(seconds: 75));
    final position = await playUntilPast(player, const Duration(seconds: 70));

    // ignore: avoid_print
    print('[seek] position after seek: $position');
    expect(position, greaterThan(const Duration(seconds: 70)));
  }, timeout: const Timeout(Duration(seconds: 180)));

  /// A DASH manifest carries every rendition YouTube offered, so the quality
  /// menu should have something in it — and pinning one should be accepted.
  testWidgets('renditions are offered and can be pinned', (tester) async {
    final (item, target) = await resolveVideo();
    if (target.format != YtStreamFormat.dash) {
      // ignore: avoid_print
      print('[quality] HLS target — renditions come from the variant list');
      return;
    }
    final (player, video) = await open(item, target);
    await playUntilPast(player, Duration.zero);

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (video.state.renditions.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    // ignore: avoid_print
    print('[quality] ${video.state.renditions.map((r) => r.label).toList()}');
    expect(video.state.renditions, isNotEmpty);

    await video.selectQualityAt(video.state.renditions.length - 1);
    await Future<void>.delayed(const Duration(seconds: 2));
    // ignore: avoid_print
    print('[quality] selected ${video.state.selectedIndex}');
    expect(video.state.isPinned, isTrue);
    expect(player.playing, isTrue, reason: 'pinning a quality stopped playback');
  }, timeout: const Timeout(Duration(seconds: 180)));
}
