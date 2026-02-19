// ignore_for_file: library_private_types_in_public_api, depend_on_referenced_packages
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/Global/index.dart';
import '/Routes/routes.dart';
import '/player/PlayerBody.dart';
import '/player/widgets/Controls.dart';
import '/player/widgets/Header.dart';
import '/controllers/AppController.dart';
import '/Helpers/AudioVisualizer.dart';
import '/widgets/common.dart';
import 'swipe_animation.dart';

// Main Player Widget
class Player extends StatefulWidget {
  const Player({super.key});

  @override
  _PlayerState createState() => _PlayerState();
}

class _PlayerState extends State<Player> with TickerProviderStateMixin {
  AnimationController? _animationController;
  Animation<double>? _animation;
  final GlobalKey<AnimatedPlayerCardState> _cardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _requestVisualizerPermission();
    _initializeAnimationController();
  }

  void _initializeAnimationController() {
    _animationController = AnimationController(
      vsync: this,
      value: 0,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _animation = Tween<double>(
      begin: 0.98,
      end: 1,
    ).animate(_animationController!);
  }

  void _requestVisualizerPermission() {
    Permission.microphone.request().then((value) {
      Visualizers.enableVisual(value.isGranted);
    });
  }

  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }

  void _onControlNext() {
    _cardKey.currentState?.animateToNext();
  }

  void _onControlPrev() {
    _cardKey.currentState?.animateToPrevious();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<AppController>(
        builder: (context, controller, child) {
          final player = controller.handler.player;
          final playerKey = Object.hash(
            controller.songId,
            identityHashCode(player),
          );

          return StreamBuilder(
            key: ValueKey(playerKey),
            stream: player.playingStream,
            builder: (context, snapshot) {
              final isPlaying = snapshot.data ?? false;

              if (isPlaying) {
                _animationController?.forward();
              } else {
                _animationController?.reverse();
              }

              return PlayerBody(
                controller: controller,
                child: Stack(
                  children: [
                    if (controller.playerVisual && isPlaying)
                      playerVisual(controller),
                    _PlayerLayout(
                      controller: controller,
                      animation: _animation!,
                      cardKey: _cardKey,
                      onControlNext: _onControlNext,
                      onControlPrev: _onControlPrev,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Main vertical layout of the player screen.
class _PlayerLayout extends StatelessWidget {
  final AppController controller;
  final Animation<double> animation;
  final GlobalKey<AnimatedPlayerCardState> cardKey;
  final VoidCallback onControlNext;
  final VoidCallback onControlPrev;

  const _PlayerLayout({
    required this.controller,
    required this.animation,
    required this.cardKey,
    required this.onControlNext,
    required this.onControlPrev,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final topPadding = mq.padding.top;
    final bottomPadding = mq.padding.bottom;
    final h = mq.size.height;

    // Responsive gap that scales with screen height
    final gap = (h * 0.015).clamp(6.0, 16.0);

    return SizedBox(
      height: h,
      width: mq.size.width,
      child: Column(
        children: [
          SizedBox(height: topPadding),
          const Header(),
          // Card deck — Expanded, artwork aligns slightly above center
          _CardDeck(
            controller: controller,
            animation: animation,
            cardKey: cardKey,
          ),
          // Track info (title + artist)
          _TrackInfo(controller: controller),
          SizedBox(height: gap),
          // Waveform seek bar
          _WaveformProgress(controller: controller),
          SizedBox(height: gap * 1.4),
          // Playback controls
          Controls(onNextPressed: onControlNext, onPrevPressed: onControlPrev),
          SizedBox(height: gap * 1.4),
          // Action bar (visualizer, queue, more)
          playerActionBar(controller, context),
          SizedBox(height: bottomPadding + gap),
        ],
      ),
    );
  }
}

/// The swiping card deck section.
class _CardDeck extends StatelessWidget {
  final AppController controller;
  final Animation<double> animation;
  final GlobalKey<AnimatedPlayerCardState> cardKey;

  const _CardDeck({
    required this.controller,
    required this.animation,
    required this.cardKey,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedPlayerCard(
        key: cardKey,
        itemCount: controller.songs.length,
        currentSongId: controller.songId,
        onPageChanged: (page) {
          if (page > controller.songId) {
            controller.next();
          } else {
            controller.prev();
          }
        },
        itemBuilder: (context, index, {bool isActive = false}) {
          return InkWell(
            onTap: () => Routes.pop(context),
            onLongPress: () => showTrackInfo(context, controller),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: playerCard(
                animation,
                context,
                controller,
                songIndex: index,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Track title and artist — shown below the card deck.
class _TrackInfo extends StatelessWidget {
  final AppController controller;
  const _TrackInfo({required this.controller});

  @override
  Widget build(BuildContext context) {
    final song = controller.songs[controller.songId];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            song.artist ?? 'Unknown artist',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

/// Waveform progress bar — uses [currentTrackPlayer] which always returns
/// the player that has the latest track loaded, even during crossfade.
class _WaveformProgress extends StatelessWidget {
  final AppController controller;

  const _WaveformProgress({required this.controller});

  @override
  Widget build(BuildContext context) {
    // currentTrackPlayer returns the incoming player during crossfade,
    // and the active player otherwise — so the waveform always tracks
    // the new track from the moment crossfade begins.
    final trackPlayer = controller.handler.currentTrackPlayer;
    final streamKey = Object.hash(
      controller.songId,
      identityHashCode(trackPlayer),
    );

    return StreamBuilder<PositionData>(
      key: ValueKey(streamKey),
      stream: Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
        trackPlayer.positionStream,
        trackPlayer.bufferedPositionStream,
        trackPlayer.durationStream,
        (position, bufferedPosition, duration) =>
            PositionData(position, bufferedPosition, duration ?? Duration.zero),
      ),
      builder: (context, snapshot) {
        final data = snapshot.data;
        return WaveformSeekBar(
          key: ValueKey('waveform_$streamKey'),
          duration: data?.duration ?? Duration.zero,
          position: data?.position ?? Duration.zero,
          bufferedPosition: data?.bufferedPosition ?? Duration.zero,
          onChangeEnd: (position) => trackPlayer.seek(position),
        );
      },
    );
  }
}
