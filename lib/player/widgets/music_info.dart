import 'package:flutter/material.dart';
import '/controllers/app_controller.dart';

class MusicInfo extends StatefulWidget {
  final AppController controller;

  const MusicInfo({super.key, required this.controller});

  @override
  State<MusicInfo> createState() => _MusicInfoState();
}

class _MusicInfoState extends State<MusicInfo>
    with SingleTickerProviderStateMixin {
  static const double _longTextThreshold = 32;
  static const double _maxScrollOffset = 400;
  static const double _defaultScrollOffset = 220;

  late final AnimationController _titleController;
  late Animation<double> _titleAnimation;
  final ScrollController _titleScrollController = ScrollController();
  final ScrollController _artistScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializeAnimationController();
  }

  void _initializeAnimationController() {
    _titleController = AnimationController(
      vsync: this,
      value: 0,
      duration: const Duration(milliseconds: 6200),
      reverseDuration: const Duration(milliseconds: 5200),
    )..repeat(reverse: true);
  }

  void _updateAnimation() {
    final currentSong = widget.controller.songs[widget.controller.songId];
    final needsLongScroll =
        currentSong.title.length > 70 || (currentSong.artist?.length ?? 0) > 70;

    _titleAnimation = Tween<double>(
      begin: -10,
      end: needsLongScroll ? _maxScrollOffset : _defaultScrollOffset,
    ).animate(_titleController);
  }

  void _handleScroll(ScrollController controller, String text) {
    if (controller.hasClients) {
      final offset = text.length > _longTextThreshold
          ? _titleAnimation.value
          : 0.0;
      controller.jumpTo(offset);
    }
  }

  Widget _buildScrollingText({
    required String text,
    required ScrollController controller,
    required TextStyle style,
    String? fallbackText,
  }) {
    return AnimatedBuilder(
      animation: _titleAnimation,
      builder: (context, child) {
        _handleScroll(controller, text);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: controller,
          child: Text(
            text.isNotEmpty ? text : fallbackText ?? '',
            maxLines: 1,
            overflow: TextOverflow.visible,
            style: style,
          ),
        );
      },
    );
  }

  Widget _buildMusicDetails() {
    final currentSong = widget.controller.songs[widget.controller.songId];
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _buildScrollingText(
          text: currentSong.title,
          controller: _titleScrollController,
          style: textTheme.headlineSmall!.apply(color: Colors.white),
        ),
        const SizedBox(height: 5),
        _buildScrollingText(
          text: currentSong.artist ?? '',
          controller: _artistScrollController,
          style: textTheme.titleMedium!.apply(
            color: Colors.white.withValues(alpha: 0.5),
          ),
          fallbackText: 'Unknown artist',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _updateAnimation();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 30),
      child: Row(children: [const SizedBox(width: 20), _buildMusicDetails()]),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleScrollController.dispose();
    _artistScrollController.dispose();
    super.dispose();
  }
}
