/// Does a music video actually play **on this phone**?
///
/// Video is the harder half: YouTube hands back separate video and audio
/// renditions, and the app combines them into a DASH manifest (see
/// `parse/yt_dash.dart`). Whether ExoPlayer accepts that manifest — and whether
/// googlevideo serves the byte ranges DASH asks for — is only answerable here.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

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

  testWidgets('a music video plays', (tester) async {
    final (item, target) = await resolveVideo();
    // ignore: avoid_print
    print('[video] "${item.title}" resolved as ${target.format.name}');

    late VideoPlayerController player;
    if (target.format == YtStreamFormat.dash) {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/itest_${item.id}.mpd');
      await file.writeAsString(target.url);
      addTearDown(() => file.delete().ignore());
      player = VideoPlayerController.file(file, httpHeaders: target.headers);
    } else {
      player = VideoPlayerController.networkUrl(
        Uri.parse(target.url),
        httpHeaders: target.headers,
        formatHint: VideoFormat.hls,
      );
    }
    addTearDown(player.dispose);

    Object? failure;
    try {
      await player.initialize();
    } catch (e) {
      failure = e;
    }
    // ignore: avoid_print
    print('[video] initialize error: $failure');
    expect(failure, isNull, reason: 'the player refused the source: $failure');

    // ignore: avoid_print
    print('[video] duration ${player.value.duration}, '
        'size ${player.value.size}');
    expect(player.value.duration, greaterThan(Duration.zero));

    unawaited(player.play());
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    var position = Duration.zero;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      position = player.value.position;
      if (position > Duration.zero) break;
    }
    // ignore: avoid_print
    print('[video] position after play: $position');
    // ignore: avoid_print
    print('[video] error: ${player.value.errorDescription}');
    expect(player.value.errorDescription, isNull);
    expect(position, greaterThan(Duration.zero),
        reason: 'the manifest loaded but no frames were produced');
  }, timeout: const Timeout(Duration(seconds: 180)));

  /// Seeking deep into a video is where large byte-range requests happen — the
  /// thing googlevideo has been observed refusing when they get too big.
  testWidgets('a music video seeks past the first megabyte', (tester) async {
    final (_, target) = await resolveVideo();
    if (target.format != YtStreamFormat.dash) {
      // ignore: avoid_print
      print('[seek] HLS target — nothing to prove about DASH ranges');
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/itest_seek.mpd');
    await file.writeAsString(target.url);
    addTearDown(() => file.delete().ignore());

    final player = VideoPlayerController.file(file, httpHeaders: target.headers);
    addTearDown(player.dispose);
    await player.initialize();
    await player.play();
    await player.seekTo(const Duration(seconds: 75));

    final deadline = DateTime.now().add(const Duration(seconds: 30));
    var position = Duration.zero;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      position = player.value.position;
      if (position > const Duration(seconds: 70)) break;
    }
    // ignore: avoid_print
    print('[seek] position after seek: $position  '
        'error: ${player.value.errorDescription}');
    expect(player.value.errorDescription, isNull);
    expect(position, greaterThan(const Duration(seconds: 70)));
  }, timeout: const Timeout(Duration(seconds: 180)));
}
