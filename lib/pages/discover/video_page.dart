/// Watching a music video.
///
/// # Two shapes, because YouTube gives two
///
/// * **HLS** — one adaptive URL that ExoPlayer and AVPlayer both play. Handed
///   over whenever YouTube offers a `hlsManifestUrl`, which measured live is
///   the minority: one of seven music videos sampled.
/// * **DASH** — a manifest this app builds from the separate video and audio
///   renditions (see `parse/yt_dash.dart`), written to a `.mpd` file so the
///   player can open it. This is what the other six need.
///
/// DASH is Android-only: AVPlayer has no DASH support, so on iOS a track with
/// no HLS says so plainly rather than handing the player something it cannot
/// open. Its audio still plays like any other track.
///
/// # The audio player is paused, not left running
///
/// Two players sharing the output would talk over each other. The music stops
/// when the video starts and does not resume on its own — the user chose to
/// watch this, and restarting the song they were listening to on the way back
/// would be its own surprise.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../controllers/AppController.dart';
import '../../services/ytmusic/yt_models.dart';
import '../../services/ytmusic/yt_repository.dart';
import 'widgets/yt_widgets.dart';

class YtVideoPage extends StatefulWidget {
  final YtTrack track;

  const YtVideoPage({super.key, required this.track});

  @override
  State<YtVideoPage> createState() => _YtVideoPageState();
}

class _YtVideoPageState extends State<YtVideoPage> {
  VideoPlayerController? _player;
  bool _loading = true;
  String? _error;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    // Silence the music before the video's own audio arrives.
    try {
      await AppController.instance.handler.pause();
    } catch (_) {
      // Nothing playing is the common case, and not an error.
    }

    try {
      final target =
          await YtMusicRepository.instance.videoTarget(widget.track.videoId);
      if (!mounted) return;

      // A DASH target is a manifest *document*, not a URL: it has to reach the
      // player as a file. AVPlayer has no DASH support at all, so on iOS this
      // is a dead end and saying so beats handing it something it can't open.
      if (target.format == YtStreamFormat.dash && Platform.isIOS) {
        setState(() {
          _loading = false;
          _error = 'YouTube only offers this one as separate video and audio '
              'streams, which iOS cannot combine. The audio plays fine.';
        });
        return;
      }

      final player = target.format == YtStreamFormat.dash
          // No `formatHint` on the file constructor — ExoPlayer infers DASH
          // from the `.mpd` extension `_writeManifest` gives it.
          ? VideoPlayerController.file(
              await _writeManifest(target.url),
              httpHeaders: target.headers,
            )
          : VideoPlayerController.networkUrl(
              Uri.parse(target.url),
              // The manifest and every segment behind it may be checked against
              // the client that resolved them.
              httpHeaders: target.headers,
              formatHint: VideoFormat.hls,
            );
      await player.initialize();
      if (!mounted) {
        await player.dispose();
        return;
      }
      await player.play();
      setState(() {
        _player = player;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // A dead target is worth forgetting so a retry re-resolves rather than
      // replaying the same expired URL.
      YtMusicRepository.instance.forget(widget.track.videoId);
      setState(() {
        _loading = false;
        _error = e is YtException ? e.message : 'That video would not play.';
      });
    }
  }

  /// Writes a generated DASH manifest somewhere the player can open it.
  ///
  /// One fixed name per track, overwritten each time: the URLs inside expire, so
  /// a manifest is worth exactly one viewing and keeping older ones around would
  /// only accumulate files that no longer play.
  Future<File> _writeManifest(String manifest) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/yt_${widget.track.videoId}.mpd');
    await file.writeAsString(manifest);
    _manifest = file;
    return file;
  }

  File? _manifest;

  @override
  void dispose() {
    _player?.dispose();
    // The manifest is only valid while the URLs inside it are.
    _manifest?.delete().ignore();
    // Landscape is offered for the video; the app is portrait everywhere else.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleFullscreen() {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    SystemChrome.setPreferredOrientations(
      landscape
          ? const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
          : const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
    );
    SystemChrome.setEnabledSystemUIMode(
      landscape ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: switch ((_loading, _error, player)) {
                // A block the shape of the video, not a spinner — the same
                // loading language the rest of Discover uses.
                (true, _, _) => AspectRatio(
                    aspectRatio: 16 / 9,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                (_, final String message, _) => YtMessage(
                    icon: Icons.videocam_off_rounded,
                    title: "That video didn't play",
                    body: message,
                    onRetry: () {
                      setState(() {
                        _loading = true;
                        _error = null;
                      });
                      _start();
                    },
                  ),
                (_, _, final VideoPlayerController controller) =>
                  GestureDetector(
                    onTap: () =>
                        setState(() => _controlsVisible = !_controlsVisible),
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                  ),
                _ => const SizedBox.shrink(),
              },
            ),
            if (player != null && _controlsVisible)
              _Controls(
                player: player,
                title: widget.track.title,
                onFullscreen: _toggleFullscreen,
              ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final VideoPlayerController player;
  final String title;
  final VoidCallback onFullscreen;

  const _Controls({
    required this.player,
    required this.title,
    required this.onFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: player,
        builder: (context, value, _) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.45),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.65),
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 52),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Center(
                child: IconButton(
                  iconSize: 56,
                  icon: Icon(
                    value.isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_filled_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () =>
                      value.isPlaying ? player.pause() : player.play(),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  const SizedBox(width: 12),
                  Text(
                    _clock(value.position),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Expanded(
                    child: VideoProgressIndicator(
                      player,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 16),
                    ),
                  ),
                  Text(
                    _clock(value.duration),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  IconButton(
                    icon: const Icon(Icons.fullscreen_rounded,
                        color: Colors.white),
                    onPressed: onFullscreen,
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  static String _clock(Duration d) {
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
