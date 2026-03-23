// ignore_for_file: library_private_types_in_public_api, depend_on_referenced_packages
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/Global/index.dart';
import '/Routes/routes.dart';
import 'player_body.dart';
import '/player/widgets/Controls.dart';
import '/player/widgets/Header.dart';
import '/controllers/AppController.dart';
import '/Helpers/AudioVisualizer.dart';
import '/Helpers/index.dart';
import '/widgets/common.dart';
import 'swipe_animation.dart';
import 'lyrics_view.dart';
import '../onboarding/coach_marks.dart';

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

  // Coach marks
  final _coachController = CoachMarkController('player');
  final _cardDeckKey = GlobalKey();
  final _controlsKey = GlobalKey();
  final _actionBarKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _requestVisualizerPermission();
    _initializeAnimationController();
    // Detect current audio output device for display
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppController>().detectAndApplyDevicePreset();
    });
    // Show coach marks on first visit (delayed to let UI settle)
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      _coachController.hasBeenShown().then((shown) {
        if (!shown && mounted) {
          _coachController.start(context, [
            CoachStep(
              targetKey: _cardDeckKey,
              title: 'Album Artwork',
              description:
                  'Swipe left or right to change tracks. Long press for track details.',
              icon: Icons.swipe_rounded,
              tooltipPosition: TooltipPosition.below,
            ),
            CoachStep(
              targetKey: _controlsKey,
              title: 'Playback Controls',
              description: 'Play, pause, skip tracks, shuffle, and repeat.',
              icon: Icons.play_circle_outline_rounded,
              tooltipPosition: TooltipPosition.above,
            ),
            CoachStep(
              targetKey: _actionBarKey,
              title: 'Quick Actions',
              description:
                  'Tap EQ for equalizer, Lyrics for synced lyrics, Visual for visualizer, Queue to manage your playlist.',
              icon: Icons.dashboard_customize_rounded,
              tooltipPosition: TooltipPosition.above,
            ),
          ]);
        }
      });
    });
  }

  void _initializeAnimationController() {
    _animationController = AnimationController(
      vsync: this,
      value: 1,
      duration: const Duration(milliseconds: 800),
    );

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

  StreamSubscription<ProcessingState>? _autoAdvanceSub;
  int _lastCompletedSongId = -1; // prevent duplicate auto-advance

  @override
  void dispose() {
    _coachController.dispose();
    _animationController?.dispose();
    _autoAdvanceSub?.cancel();
    super.dispose();
  }

  void _onControlNext() {
    final ctrl = context.read<AppController>();
    if (ctrl.songs.isEmpty) return;
    // Animate card, then onPageChanged will call ctrl.next()
    _cardKey.currentState?.animateToNext();
  }

  void _onControlPrev() {
    final ctrl = context.read<AppController>();
    if (ctrl.songs.isEmpty) return;
    // Prev always acts immediately — no card throw animation
    // (card deck only stacks forward, not backward)
    ctrl.prev();
  }

  void _setupAutoAdvanceListener(AppController controller) {
    _autoAdvanceSub?.cancel();
    _autoAdvanceSub = controller.handler.player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && mounted) {
        // Prevent duplicate: only trigger once per song completion
        final currentId = controller.songId;
        if (currentId == _lastCompletedSongId) return;
        _lastCompletedSongId = currentId;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _cardKey.currentState?.animateAutoAdvance();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<AppController>(
        builder: (context, controller, child) {
          // Set up auto-advance listener once
          if (_autoAdvanceSub == null) {
            _setupAutoAdvanceListener(controller);
          }

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
                      cardDeckKey: _cardDeckKey,
                      controlsKey: _controlsKey,
                      actionBarKey: _actionBarKey,
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

/// Main layout of the player screen — portrait or landscape.
class _PlayerLayout extends StatelessWidget {
  final AppController controller;
  final Animation<double> animation;
  final GlobalKey<AnimatedPlayerCardState> cardKey;
  final VoidCallback onControlNext;
  final VoidCallback onControlPrev;
  final GlobalKey cardDeckKey;
  final GlobalKey controlsKey;
  final GlobalKey actionBarKey;

  const _PlayerLayout({
    required this.controller,
    required this.animation,
    required this.cardKey,
    required this.onControlNext,
    required this.onControlPrev,
    required this.cardDeckKey,
    required this.controlsKey,
    required this.actionBarKey,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isLandscape = mq.orientation == Orientation.landscape;

    if (isLandscape) {
      return _buildLandscape(context, mq);
    }
    return _buildPortrait(context, mq);
  }

  // ── Portrait (original vertical stack) ──────────────────────────────────

  Widget _buildPortrait(BuildContext context, MediaQueryData mq) {
    final topPadding = mq.padding.top;
    final bottomPadding = mq.padding.bottom;
    final h = mq.size.height;
    final gap = (h * 0.015).clamp(6.0, 16.0);

    return SizedBox(
      height: h,
      width: mq.size.width,
      child: Column(
        children: [
          SizedBox(height: topPadding),
          const Header(),
          _CardDeck(
            controller: controller,
            animation: animation,
            cardKey: cardKey,
            spotlightKey: cardDeckKey,
          ),
          _TrackInfo(controller: controller),
          SizedBox(height: gap),
          _WaveformProgress(controller: controller),
          SizedBox(height: gap * 1.4),
          KeyedSubtree(
            key: controlsKey,
            child: Controls(onNextPressed: onControlNext, onPrevPressed: onControlPrev),
          ),
          SizedBox(height: gap * 1.4),
          KeyedSubtree(
            key: actionBarKey,
            child: playerActionBar(controller, context),
          ),
          SizedBox(height: bottomPadding + gap),
        ],
      ),
    );
  }

  // ── Landscape (artwork left, controls right) ────────────────────────────

  Widget _buildLandscape(BuildContext context, MediaQueryData mq) {
    final topPadding = mq.padding.top;
    final bottomPadding = mq.padding.bottom;
    final leftPadding = mq.padding.left;
    final rightPadding = mq.padding.right;
    final h = mq.size.height;
    final gap = (h * 0.02).clamp(6.0, 14.0);

    return SizedBox(
      height: h,
      width: mq.size.width,
      child: Column(
        children: [
          SizedBox(height: topPadding),
          const Header(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Left: artwork card deck + track info ──
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: EdgeInsets.only(left: leftPadding + 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _CardDeck(
                          controller: controller,
                          animation: animation,
                          cardKey: cardKey,
                          landscape: true,
                          spotlightKey: cardDeckKey,
                        ),
                        _TrackInfo(controller: controller),
                      ],
                    ),
                  ),
                ),
                // ── Right: seekbar, controls, action bar ──
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: EdgeInsets.only(right: rightPadding + 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _WaveformProgress(controller: controller),
                        SizedBox(height: gap * 1.4),
                        KeyedSubtree(
                          key: controlsKey,
                          child: Controls(
                            onNextPressed: onControlNext,
                            onPrevPressed: onControlPrev,
                          ),
                        ),
                        SizedBox(height: gap * 1.4),
                        KeyedSubtree(
                          key: actionBarKey,
                          child: playerActionBar(controller, context),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: bottomPadding),
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
  final bool landscape;
  final GlobalKey? spotlightKey;

  const _CardDeck({
    required this.controller,
    required this.animation,
    required this.cardKey,
    this.landscape = false,
    this.spotlightKey,
  });

  void _openLyrics(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, _, _) => const LyricsView(),
        transitionsBuilder: (_, anim, _, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardContent = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragEnd: (details) {
        if (details.velocity.pixelsPerSecond.dy < -300) {
          _openLyrics(context);
        }
      },
      child: Column(
        children: [
          Expanded(
            child: AnimatedPlayerCard(
              key: cardKey,
              itemCount: controller.songs.length,
              currentSongId: controller.songId,
              onPageChanged: (page) {
                if (page > controller.songId) {
                  controller.next();
                } else if (page < controller.songId) {
                  // Skip the >3s restart check — card already animated,
                  // user explicitly chose previous track
                  controller.songId = page;
                  controller.artWorkId = controller.songs[page].id;
                  loadAudioSource(controller.handler, controller.songs[page],
                      replayGain: controller.replayGain);
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
          ),
          if (controller.currentLyrics != null || controller.lyricsLoading)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Icon(
                Icons.keyboard_arrow_up_rounded,
                color: Colors.white.withValues(alpha: 0.25),
                size: 20,
              ),
            ),
        ],
      ),
    );

    final card = spotlightKey != null
        ? KeyedSubtree(key: spotlightKey, child: cardContent)
        : cardContent;

    // In landscape the parent Column is centered — use a constrained size
    // instead of Expanded so mainAxisAlignment: center can work.
    if (landscape) {
      final availableHeight =
          MediaQuery.of(context).size.height -
          MediaQuery.of(context).padding.top -
          MediaQuery.of(context).padding.bottom -
          48; // header height
      // Card takes ~60% of available height, leaves room for track info
      final cardHeight = (availableHeight * 0.65).clamp(120.0, 400.0);
      return SizedBox(height: cardHeight, child: card);
    }

    return Expanded(child: card);
  }
}

/// Track title, artist, and album — shown below the card deck.
/// Long text auto-scrolls horizontally (marquee).
class _TrackInfo extends StatelessWidget {
  final AppController controller;
  const _TrackInfo({required this.controller});

  static const _deviceInfo = <String, (IconData, String)>{
    'speaker': (Icons.speaker_rounded, 'Speaker'),
    'bluetooth': (Icons.bluetooth_audio_rounded, 'Bluetooth'),
    'wired_headphone': (Icons.headphones_rounded, 'Headphones'),
    'usb_audio': (Icons.usb_rounded, 'USB Audio'),
  };

  @override
  Widget build(BuildContext context) {
    final song = controller.songs[controller.songId];
    final duration = formatTime(Duration(milliseconds: song.duration ?? 0));
    final ext = song.fileExtension.toUpperCase();
    final device = controller.lastOutputDevice;
    final (deviceIcon, deviceLabel) =
        _deviceInfo[device] ?? (Icons.speaker_rounded, 'Speaker');

    final dimStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.4),
      fontSize: 12,
      fontWeight: FontWeight.w400,
    );
    final dotStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.3),
      fontSize: 12,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MarqueeText(
            text: song.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          _MarqueeText(
            text: song.artist ?? 'Unknown artist',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (song.album != null &&
                  song.album!.isNotEmpty &&
                  !song.album!.startsWith('http')) ...[
                Flexible(
                  child: Text(
                    song.album!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dimStyle,
                  ),
                ),
                Text('  \u2022  ', style: dotStyle),
              ],
              Text(duration, style: dimStyle),
              if (ext.isNotEmpty) ...[
                Text('  \u2022  ', style: dotStyle),
                Text(ext, style: dimStyle),
              ],
              Text('  \u2022  ', style: dotStyle),
              Icon(
                deviceIcon,
                size: 13,
                color: Colors.white.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 3),
              Text(deviceLabel, style: dimStyle),
            ],
          ),
        ],
      ),
    );
  }
}

/// Auto-scrolling text that scrolls when the text overflows.
class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _MarqueeText({required this.text, required this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  bool _overflows = false;
  AnimationController? _anim;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  @override
  void didUpdateWidget(_MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _anim?.stop();
      _anim?.dispose();
      _anim = null;
      _scrollController.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
    }
  }

  void _checkOverflow() {
    if (!mounted) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final overflows = maxScroll > 0;
    if (overflows != _overflows) {
      setState(() => _overflows = overflows);
    }
    if (overflows) {
      _startScroll(maxScroll);
    }
  }

  void _startScroll(double maxScroll) {
    _anim?.dispose();
    // Speed: ~30px/s — adjust duration based on overflow distance.
    final durationMs = (maxScroll / 30 * 1000).round().clamp(2000, 15000);
    _anim =
        AnimationController(
          vsync: this,
          duration: Duration(milliseconds: durationMs),
        )..addListener(() {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_anim!.value * maxScroll);
          }
        });

    // Pause 1.5s → scroll to end → pause 1.5s → jump back → repeat
    Future.doWhile(() async {
      if (!mounted) return false;
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return false;
      await _anim!.forward(from: 0);
      if (!mounted) return false;
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted || !_scrollController.hasClients) return false;
      _scrollController.jumpTo(0);
      return mounted;
    });
  }

  @override
  void dispose() {
    _anim?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.style.fontSize! * 1.4,
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(
          widget.text,
          maxLines: 1,
          softWrap: false,
          style: widget.style,
        ),
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

    return StreamBuilder<bool>(
      key: ValueKey('playing_$streamKey'),
      stream: trackPlayer.playingStream,
      builder: (context, playingSnap) {
        final isPlaying = playingSnap.data ?? false;
        return StreamBuilder<PositionData>(
          key: ValueKey(streamKey),
          stream:
              Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
                trackPlayer.positionStream,
                trackPlayer.bufferedPositionStream,
                trackPlayer.durationStream,
                (position, bufferedPosition, duration) => PositionData(
                  position,
                  bufferedPosition,
                  duration ?? Duration.zero,
                ),
              ),
          builder: (context, snapshot) {
            final data = snapshot.data;
            return WaveformSeekBar(
              key: ValueKey('waveform_$streamKey'),
              duration: data?.duration ?? Duration.zero,
              position: data?.position ?? Duration.zero,
              bufferedPosition: data?.bufferedPosition ?? Duration.zero,
              isPlaying: isPlaying,
              onChangeEnd: (position) => trackPlayer.seek(position),
            );
          },
        );
      },
    );
  }
}
