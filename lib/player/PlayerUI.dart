import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:swipable_stack/swipable_stack.dart';
import '../Helpers/Channel.dart';
import '../Helpers/AudioVisualizer.dart';
import '../Global/index.dart';
import '../Routes/routes.dart';
import '../controllers/AppController.dart';
import '../widgets/common.dart';
import 'PlayerBody.dart';
import 'widgets/Controls.dart';
import 'widgets/Header.dart';
import 'widgets/MusicInfo.dart';

class Player extends StatefulWidget {
  const Player({super.key});

  @override
  State<Player> createState() => _PlayerState();
}

class _PlayerState extends State<Player> with TickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _initializeAnimation();
    _checkPermissionForAudioVisualization();
  }

  void _initializeAnimation() {
    _animationController = AnimationController(
      vsync: this,
      value: 0,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _animation = Tween<double>(
      begin: 0.98,
      end: 1,
    ).animate(_animationController);
  }

  Future<void> _checkPermissionForAudioVisualization() async {
    final status = await Permission.microphone.request();
    Visualizers.enableVisual(status.isGranted);
  }

  Stream<PositionData> get _positionDataStream {
    final controller = context.read<AppController>();
    return Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
      controller.handler.player.positionStream,
      controller.handler.player.bufferedPositionStream,
      controller.handler.player.durationStream,
      (position, bufferedPosition, duration) => PositionData(
        position,
        bufferedPosition,
        duration ?? Duration.zero,
      ),
    );
  }

  void _handlePageChange(
      int index, AppController controller, SwipeDirection direction) {
    if (direction == SwipeDirection.right) {
      controller.prev();
    } else if (direction == SwipeDirection.left) {
      controller.next();
    }
    setState(() {
      loadAudioSource(controller.handler, controller.songs[controller.songId]);
    });
  }

  Widget _buildPlayerContent(AppController controller, bool? isPlaying) {
    if (isPlaying != null && isPlaying) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }

    return PlayerBody(
      controller: controller,
      child: Stack(
        children: [
          if (controller.playerVisual && isPlaying != null)
            playerVisual(controller),
          _buildMainContent(controller),
        ],
      ),
    );
  }

  Widget _buildMainContent(AppController controller) {
    final size = MediaQuery.of(context).size;

    return FittedBox(
      child: SizedBox(
        height: size.height,
        width: size.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: MediaQuery.of(context).padding.top),
            const Header(),
            _buildSwipeableStack(controller),
            _buildSeekBar(),
            const Controls(),
          ],
        ),
      ),
    );
  }

  Widget _buildSwipeableStack(AppController controller) {
    final size = MediaQuery.of(context).size;

    return SizedBox(
      height: size.height - 280,
      child: SwipableStack(
        itemCount: controller.songs.length,
        onSwipeCompleted: (index, direction) {
          _handlePageChange(index, controller, direction);
        },
        builder: (context, constraints) {
          return _buildPageViewItem(controller, constraints.index);
        },
      ),
    );
  }

  Widget _buildPageViewItem(AppController controller, int index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => Routes.pop(context),
          onLongPress: () => showTrackInfo(context, controller),
          child: playerCard(_animation, context, controller),
        ),
        MusicInfo(controller: controller),
      ],
    );
  }

  Widget _buildSeekBar() {
    return FittedBox(
      child: SizedBox(
        width: MediaQuery.of(context).size.width,
        child: StreamBuilder<PositionData>(
          stream: _positionDataStream,
          builder: (context, snapshot) {
            final positionData = snapshot.data;
            return SeekBar(
              duration: positionData?.duration ?? Duration.zero,
              position: positionData?.position ?? Duration.zero,
              bufferedPosition: positionData?.bufferedPosition ?? Duration.zero,
              onChangeEnd: context.read<AppController>().handler.player.seek,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<AppController>(
        builder: (context, controller, _) {
          if (controller.songId >= (controller.songs.length - 1)) {
            Channel.showNativeMessage("Songs playlist ended.");
          }

          if (controller.visuals) {
            Visualizers.enableVisual(true);
          }

          return StreamBuilder<bool>(
            stream: controller.handler.player.playingStream,
            builder: (context, snapshot) =>
                _buildPlayerContent(controller, snapshot.data),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
