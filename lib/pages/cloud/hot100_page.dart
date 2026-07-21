import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../Routes/routes.dart';
import '../../controllers/AppController.dart';
import '../../services/hot100/hot100_model.dart';
import '../../services/hot100/hot100_repository.dart';

class Hot100Page extends StatefulWidget {
  const Hot100Page({super.key});

  @override
  State<Hot100Page> createState() => _Hot100PageState();
}

class _Hot100PageState extends State<Hot100Page>
    with SingleTickerProviderStateMixin {
  final _repo = Hot100RepositoryImpl();
  List<Hot100Song> _songs = [];
  bool _loading = true;
  String? _error;
  late AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _loadChart();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadChart() async {
    _shimmerCtrl.repeat();
    setState(() { _loading = true; _error = null; });

    final result = await _repo.fetchChart();
    if (!mounted) return;

    result.fold(
      (failure) => setState(() {
        _loading = false;
        _error = failure.message;
        _shimmerCtrl.stop();
      }),
      (songs) => setState(() {
        _loading = false;
        _songs = songs;
        _shimmerCtrl.stop();
      }),
    );
  }

  void _playSong(int index) {
    final controller = context.read<AppController>();
    final songModels = _songs.map((s) => SongModel({
      '_id': s.url.hashCode.abs(),
      '_data': s.url,
      'title': s.title,
      'artist': s.artist,
      'album': s.artWork,
      'duration': 0,
      '_display_name': '${s.title}.mp3',
      '_display_name_wo_ext': s.title,
      '_size': 0,
      'file_extension': 'mp3',
      'is_music': true,
    })).toList();

    controller.playSongFromList(songModels, index);
    Routes.playerTo(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFD4A825).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_fire_department_rounded,
                      color: Color(0xFFD4A825), size: 16),
                  SizedBox(width: 4),
                  Text('HOT 100',
                      style: TextStyle(
                        color: Color(0xFFD4A825),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      )),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('Ugandan Music',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return _SongListSkeleton(controller: _shimmerCtrl);
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 48,
                  color: theme.colorScheme.error.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _loadChart,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_songs.isEmpty) {
      return Center(
        child: Text('No songs available',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            )),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _songs.length,
      itemBuilder: (context, index) {
        final song = _songs[index];
        final rank = index + 1;

        return InkWell(
          onTap: () => _playSong(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '$rank',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: rank <= 3 ? FontWeight.w700 : FontWeight.w500,
                      color: rank <= 3
                          ? const Color(0xFFD4A825)
                          : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(
                    imageUrl: song.artWork,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      width: 44, height: 44,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      width: 44, height: 44,
                      color: Colors.white.withValues(alpha: 0.05),
                      child: const Icon(Icons.music_note, size: 20, color: Colors.white24),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          )),
                      Text(song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          )),
                    ],
                  ),
                ),
                Icon(Icons.play_circle_outline_rounded, size: 24,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// Skeleton loader for song list pages
// =============================================================================

class _SongListSkeleton extends StatelessWidget {
  final AnimationController controller;
  const _SongListSkeleton({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest;
    final highlight = theme.colorScheme.surfaceContainerLow;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: 12,
          itemBuilder: (_, i) {
            final off = (controller.value + i * 0.06) % 1.0;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  _ShimmerBox(width: 28, height: 14, offset: off,
                      base: base, highlight: highlight),
                  const SizedBox(width: 10),
                  _ShimmerBox(width: 44, height: 44, radius: 6, offset: off,
                      base: base, highlight: highlight),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ShimmerBox(width: 140, height: 12, offset: off,
                            base: base, highlight: highlight),
                        const SizedBox(height: 6),
                        _ShimmerBox(width: 90, height: 10, offset: off,
                            base: base, highlight: highlight),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  final double width, height;
  final double radius;
  final double offset;
  final Color base, highlight;

  const _ShimmerBox({
    required this.width,
    required this.height,
    this.radius = 4,
    required this.offset,
    required this.base,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          colors: [base, highlight, base],
          stops: const [0.0, 0.5, 1.0],
          begin: Alignment(-1.0 + 2.0 * offset, 0),
          end: Alignment(1.0 + 2.0 * offset, 0),
        ),
      ),
    );
  }
}
