import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../Routes/routes.dart';
import '../../services/music/music_models.dart';
import '../../services/music/music_player_helper.dart';
import '../../services/music/music_repository.dart';
import 'song_detail_page.dart';

class PopularPage extends StatefulWidget {
  const PopularPage({super.key});

  @override
  State<PopularPage> createState() => _PopularPageState();
}

class _PopularPageState extends State<PopularPage>
    with SingleTickerProviderStateMixin {
  final _repo = MusicRepositoryImpl();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final List<MusicSong> _songs = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  String? _error;
  String _searchQuery = '';
  late AnimationController _shimmerCtrl;

  List<MusicSong> get _filtered {
    if (_searchQuery.isEmpty) return _songs;
    final q = _searchQuery.toLowerCase();
    return _songs
        .where((s) =>
            s.title.toLowerCase().contains(q) ||
            s.artist.toLowerCase().contains(q))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _scrollController.addListener(_onScroll);
    _loadPage();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_searchQuery.isNotEmpty) return; // no pagination while filtering
    if (_hasMore &&
        !_loadingMore &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300) {
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    if (_loadingMore) return;
    // Shimmer drives both the full-page skeleton and the load-more skeleton.
    _shimmerCtrl.repeat();
    setState(() {
      if (_songs.isEmpty) _loading = true;
      _loadingMore = true;
      _error = null;
    });

    final result = await _repo.fetchPopular(offset: _offset);
    if (!mounted) return;

    result.fold(
      (f) => setState(() {
        _loading = false;
        _loadingMore = false;
        _error = f.message;
        _shimmerCtrl.stop();
      }),
      (songs) => setState(() {
        _loading = false;
        _loadingMore = false;
        _songs.addAll(songs);
        _hasMore = songs.length >= 50;
        _offset += 55;
        _shimmerCtrl.stop();
      }),
    );
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
          ],
        ),
        actions: [
          if (_songs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  _searchQuery.isEmpty
                      ? '${_songs.length} songs'
                      : '${_filtered.length} of ${_songs.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search songs...',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                prefixIcon: Icon(Icons.search_rounded,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return _SongListSkeleton(controller: _shimmerCtrl);
    }

    if (_error != null && _songs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded,
                  size: 48,
                  color: theme.colorScheme.error.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _loadPage,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final displayed = _filtered;

    if (displayed.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _searchQuery.isNotEmpty
                  ? Icons.search_off_rounded
                  : Icons.music_off_rounded,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No songs matching "$_searchQuery"'
                  : 'No songs found',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      itemCount: displayed.length + (_searchQuery.isEmpty && _loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= displayed.length) {
          return _LoadMoreSkeleton(controller: _shimmerCtrl);
        }

        final song = displayed[index];
        // Rank reflects original position in full list
        final rank = _searchQuery.isEmpty ? index + 1 : _songs.indexOf(song) + 1;
        return _PopularTile(
          song: song,
          rank: rank,
          onTap: () => MusicPlayerHelper.playFromList(context, displayed, index),
          onLongPress: () =>
              Routes.routeTo(SongDetailPage(songId: song.id), context),
        );
      },
    );
  }
}

// =============================================================================
// Skeleton loaders
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

class _LoadMoreSkeleton extends StatelessWidget {
  final AnimationController controller;
  const _LoadMoreSkeleton({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest;
    final highlight = theme.colorScheme.surfaceContainerLow;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          children: List.generate(3, (i) {
            final off = (controller.value + i * 0.08) % 1.0;
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
          }),
        );
      },
    );
  }
}

// =============================================================================
// Song tile widget
// =============================================================================

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
// Shimmer box (reusable)
// =============================================================================

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
