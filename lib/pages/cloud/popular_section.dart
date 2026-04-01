import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../Routes/routes.dart';
import '../../services/music/music_models.dart';
import '../../services/music/music_player_helper.dart';
import '../../services/music/music_repository.dart';
import 'popular_page.dart';
import 'song_detail_page.dart';

class PopularSection extends StatefulWidget {
  const PopularSection({super.key});

  @override
  State<PopularSection> createState() => _PopularSectionState();
}

class _PopularSectionState extends State<PopularSection>
    with SingleTickerProviderStateMixin {
  final _repo = MusicRepositoryImpl();
  List<MusicSong> _songs = [];
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
    _load();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });

    final result = await _repo.fetchPopular();
    if (!mounted) return;

    result.fold(
      (f) => setState(() { _loading = false; _error = f.message; }),
      (songs) => setState(() { _loading = false; _songs = songs; }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) return _PopularSkeleton(controller: _shimmerCtrl);

    if (_error != null && _songs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 40,
                color: theme.colorScheme.error.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            Text(_error!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_songs.isEmpty) return const SizedBox.shrink();

    final previewCount = _songs.length.clamp(0, 5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.trending_up_rounded,
                        color: theme.colorScheme.primary, size: 16),
                    const SizedBox(width: 4),
                    Text('POPULAR',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        )),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
        ),

        // Horizontal scroll — top 10 featured
        SizedBox(
          height: 190,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _songs.length.clamp(0, 10),
            itemBuilder: (context, index) {
              final song = _songs[index];
              return _PopularCard(
                song: song,
                rank: index + 1,
                onTap: () =>
                    MusicPlayerHelper.playFromList(context, _songs, index),
                onLongPress: () => Routes.routeTo(
                    SongDetailPage(songId: song.id), context),
              );
            },
          ),
        ),

        const SizedBox(height: 8),

        // Preview list (5 items)
        ...List.generate(previewCount, (index) {
          final song = _songs[index];
          return _PopularTile(
            song: song,
            rank: index + 1,
            onTap: () =>
                MusicPlayerHelper.playFromList(context, _songs, index),
            onLongPress: () =>
                Routes.routeTo(SongDetailPage(songId: song.id), context),
          );
        }),

        // View More
        if (_songs.length > 5)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () =>
                    Routes.routeTo(const PopularPage(), context),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  'View More',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Skeleton loader
// =============================================================================

class _PopularSkeleton extends StatelessWidget {
  final AnimationController controller;
  const _PopularSkeleton({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest;
    final highlight = theme.colorScheme.surfaceContainerLow;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: _ShimmerBar(
                  width: 100, height: 24, offset: controller.value,
                  base: base, highlight: highlight),
            ),
            // Horizontal cards
            SizedBox(
              height: 190,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: 4,
                itemBuilder: (_, i) {
                  final off = (controller.value + i * 0.1) % 1.0;
                  return Container(
                    width: 140,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ShimmerBar(width: 140, height: 140, radius: 10,
                            offset: off, base: base, highlight: highlight),
                        const SizedBox(height: 6),
                        _ShimmerBar(width: 100, height: 12, offset: off,
                            base: base, highlight: highlight),
                        const SizedBox(height: 4),
                        _ShimmerBar(width: 70, height: 10, offset: off,
                            base: base, highlight: highlight),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            // List tiles
            ...List.generate(6, (i) {
              final off = (controller.value + i * 0.08) % 1.0;
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    _ShimmerBar(width: 28, height: 14, offset: off,
                        base: base, highlight: highlight),
                    const SizedBox(width: 10),
                    _ShimmerBar(width: 44, height: 44, radius: 6,
                        offset: off, base: base, highlight: highlight),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ShimmerBar(width: 140, height: 12, offset: off,
                              base: base, highlight: highlight),
                          const SizedBox(height: 4),
                          _ShimmerBar(width: 90, height: 10, offset: off,
                              base: base, highlight: highlight),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

// =============================================================================
// Song card & tile widgets
// =============================================================================

class _PopularCard extends StatelessWidget {
  final MusicSong song;
  final int rank;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PopularCard({
    required this.song,
    required this.rank,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 140,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: song.artwork,
                    width: 140,
                    height: 140,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: Colors.white.withValues(alpha: 0.05),
                      child:
                          const Icon(Icons.music_note, color: Colors.white24),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.white.withValues(alpha: 0.05),
                      child:
                          const Icon(Icons.music_note, color: Colors.white24),
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('#$rank',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
            Text(song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                )),
          ],
        ),
      ),
    );
  }
}

class _PopularTile extends StatelessWidget {
  final MusicSong song;
  final int rank;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PopularTile({
    required this.song,
    required this.rank,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
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
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: song.artwork,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 44,
                  height: 44,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 44,
                  height: 44,
                  color: Colors.white.withValues(alpha: 0.05),
                  child: const Icon(Icons.music_note,
                      size: 20, color: Colors.white24),
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
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w500)),
                  Text(song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5),
                      )),
                ],
              ),
            ),
            Icon(Icons.play_circle_outline_rounded,
                size: 24,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Shimmer bar (reusable)
// =============================================================================

class _ShimmerBar extends StatelessWidget {
  final double width, height;
  final double radius;
  final double offset;
  final Color base, highlight;

  const _ShimmerBar({
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
