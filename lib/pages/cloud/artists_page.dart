import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../Routes/routes.dart';
import '../../services/music/music_models.dart';
import '../../services/music/music_repository.dart';
import '../../widgets/pinch_zoom_grid.dart';
import 'artist_detail_page.dart';

class ArtistsPage extends StatefulWidget {
  const ArtistsPage({super.key});

  @override
  State<ArtistsPage> createState() => _ArtistsPageState();
}

class _ArtistsPageState extends State<ArtistsPage>
    with SingleTickerProviderStateMixin {
  final _repo = MusicRepositoryImpl();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final List<MusicArtist> _artists = [];

  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  String _searchQuery = '';
  Timer? _debounce;
  late AnimationController _shimmerCtrl;

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
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore || _searchQuery.isNotEmpty) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 200) {
      _loadPage();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (value.trim() == _searchQuery) return;
      setState(() {
        _searchQuery = value.trim();
        _artists.clear();
        _page = 1;
        _hasMore = true;
        _loading = true;
      });
      _loadPage();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _artists.clear();
      _page = 1;
      _hasMore = true;
      _loading = true;
    });
    _loadPage();
  }

  Future<void> _loadPage() async {
    if (_loadingMore && !_loading) return;

    // Shimmer drives both the full-grid skeleton and the load-more tiles.
    _shimmerCtrl.repeat();
    setState(() {
      if (_page == 1) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });

    final result = await _repo.fetchArtists(
      page: _searchQuery.isEmpty ? _page : null,
      query: _searchQuery.isNotEmpty ? _searchQuery : null,
    );
    if (!mounted) return;

    result.fold(
      (f) => setState(() {
        _shimmerCtrl.stop();
        _loading = false;
        _loadingMore = false;
        if (_page == 1) _error = f.message;
      }),
      (artists) => setState(() {
        _shimmerCtrl.stop();
        _loading = false;
        _loadingMore = false;
        if (artists.isEmpty) {
          _hasMore = false;
        } else {
          _artists.addAll(artists);
          _page++;
        }
        // Search results come as a single filtered list — no pagination
        if (_searchQuery.isNotEmpty) _hasMore = false;
      }),
    );
  }

  void _retry() {
    _page = 1;
    _artists.clear();
    _hasMore = true;
    _loadPage();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Artists')),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search artists...',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                prefixIcon: Icon(Icons.search_rounded,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 20),
                        onPressed: _clearSearch,
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

          // Body
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return _ArtistGridSkeleton(controller: _shimmerCtrl);
    }

    if (_error != null && _artists.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: _retry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_artists.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _searchQuery.isNotEmpty
                  ? Icons.search_off_rounded
                  : Icons.people_outline_rounded,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No artists matching "$_searchQuery"'
                  : 'No artists found',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    return PinchZoomGrid(
      initialExtent: 140.0,
      minExtent: 80.0,
      maxExtent: 200.0,
      gridBuilder: (extent) => GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: extent,
          mainAxisSpacing: 16,
          crossAxisSpacing: 12,
          childAspectRatio: 0.75,
        ),
        itemCount: _artists.length + (_loadingMore ? 3 : 0),
        itemBuilder: (context, index) {
          if (index >= _artists.length) {
            final off =
                (_shimmerCtrl.value + (index - _artists.length) * 0.1) % 1.0;
            return AnimatedBuilder(
              animation: _shimmerCtrl,
              builder: (context, _) => _ArtistSkeletonTile(
                offset: off,
                base: theme.colorScheme.surfaceContainerHighest,
                highlight: theme.colorScheme.surfaceContainerLow,
              ),
            );
          }

          final artist = _artists[index];
          return _ArtistGridTile(
            artist: artist,
            onTap: () {
              final slug = artist.name.replaceAll(' ', '-');
              Routes.routeTo(
                ArtistDetailPage(
                  slug: slug,
                  artistId: artist.id,
                  name: artist.name,
                  imageUrl: artist.image,
                ),
                context,
              );
            },
          );
        },
      ),
    );
  }
}

// =============================================================================
// Skeleton loaders
// =============================================================================

class _ArtistGridSkeleton extends StatelessWidget {
  final AnimationController controller;
  const _ArtistGridSkeleton({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest;
    final highlight = theme.colorScheme.surfaceContainerLow;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 140,
            mainAxisSpacing: 16,
            crossAxisSpacing: 12,
            childAspectRatio: 0.75,
          ),
          itemCount: 12,
          itemBuilder: (_, i) {
            final off = (controller.value + i * 0.06) % 1.0;
            return _ArtistSkeletonTile(
                offset: off, base: base, highlight: highlight);
          },
        );
      },
    );
  }
}

class _ArtistSkeletonTile extends StatelessWidget {
  final double offset;
  final Color base, highlight;
  const _ArtistSkeletonTile({
    required this.offset,
    required this.base,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final avatarSize = constraints.maxWidth * 0.7;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: avatarSize,
              height: avatarSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [base, highlight, base],
                  stops: const [0.0, 0.5, 1.0],
                  begin: Alignment(-1.0 + 2.0 * offset, 0),
                  end: Alignment(1.0 + 2.0 * offset, 0),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: avatarSize * 0.75,
              height: 12,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  colors: [base, highlight, base],
                  stops: const [0.0, 0.5, 1.0],
                  begin: Alignment(-1.0 + 2.0 * offset, 0),
                  end: Alignment(1.0 + 2.0 * offset, 0),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// =============================================================================
// Artist grid tile
// =============================================================================

class _ArtistGridTile extends StatelessWidget {
  final MusicArtist artist;
  final VoidCallback onTap;

  const _ArtistGridTile({required this.artist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final avatarSize = constraints.maxWidth * 0.7;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: CachedNetworkImage(
                  imageUrl: artist.image,
                  width: avatarSize,
                  height: avatarSize,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    width: avatarSize,
                    height: avatarSize,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(Icons.person,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: avatarSize,
                    height: avatarSize,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(Icons.person,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                artist.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
