import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/music/music_models.dart';
import '../../services/music/music_player_helper.dart';
import '../../services/music/music_repository.dart';
import 'song_detail_page.dart';

class ArtistDetailPage extends StatefulWidget {
  final String slug;
  final String artistId;
  final String name;
  final String imageUrl;

  const ArtistDetailPage({
    super.key,
    required this.slug,
    required this.artistId,
    required this.name,
    required this.imageUrl,
  });

  @override
  State<ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends State<ArtistDetailPage>
    with SingleTickerProviderStateMixin {
  final _repo = MusicRepositoryImpl();
  MusicArtistDetail? _artist;
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
    _shimmerCtrl.repeat();
    setState(() {
      _loading = true;
      _error = null;
    });
    final result =
        await _repo.fetchArtistDetail(widget.slug, widget.artistId);
    if (!mounted) return;
    result.fold(
      (f) => setState(() {
        _loading = false;
        _error = f.message;
        _shimmerCtrl.stop();
      }),
      (artist) => setState(() {
        _loading = false;
        _artist = artist;
        _shimmerCtrl.stop();
      }),
    );
  }

  String _formatNumber(int? n) {
    if (n == null) return '-';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Always show header with artist cover image
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                _artist?.name ?? widget.name,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: _artist?.image ?? widget.imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: theme.colorScheme.surfaceContainerHigh,
                      child: const Icon(Icons.person,
                          size: 60, color: Colors.white24),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Body: loading / error / content
          if (_loading) _buildSkeleton(theme),
          if (!_loading && _error != null) _buildError(theme),
          if (!_loading && _error == null && _artist != null)
            ..._buildContent(theme),
        ],
      ),
    );
  }

  SliverToBoxAdapter _buildSkeleton(ThemeData theme) {
    final base = theme.colorScheme.surfaceContainerHighest;
    final highlight = theme.colorScheme.surfaceContainerLow;

    return SliverToBoxAdapter(
      child: AnimatedBuilder(
        animation: _shimmerCtrl,
        builder: (context, _) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats skeleton
                Row(
                  children: [
                    _ShimmerBar(width: 70, height: 28, radius: 14,
                        offset: _shimmerCtrl.value, base: base, highlight: highlight),
                    const SizedBox(width: 12),
                    _ShimmerBar(width: 50, height: 14,
                        offset: _shimmerCtrl.value, base: base, highlight: highlight),
                    const SizedBox(width: 12),
                    _ShimmerBar(width: 50, height: 14,
                        offset: _shimmerCtrl.value, base: base, highlight: highlight),
                  ],
                ),
                const SizedBox(height: 16),
                // Bio skeleton
                ...List.generate(3, (i) {
                  final off = (_shimmerCtrl.value + i * 0.1) % 1.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _ShimmerBar(
                        width: i == 2 ? 200 : double.infinity, height: 12,
                        offset: off, base: base, highlight: highlight),
                  );
                }),
                const SizedBox(height: 20),
                _ShimmerBar(width: 60, height: 18,
                    offset: _shimmerCtrl.value, base: base, highlight: highlight),
                const SizedBox(height: 12),
                // Song tile skeletons
                ...List.generate(6, (i) {
                  final off = (_shimmerCtrl.value + i * 0.08) % 1.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        _ShimmerBar(width: 48, height: 48, radius: 6,
                            offset: off, base: base, highlight: highlight),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ShimmerBar(width: 150, height: 12,
                                  offset: off, base: base, highlight: highlight),
                              const SizedBox(height: 4),
                              _ShimmerBar(width: 90, height: 10,
                                  offset: off, base: base, highlight: highlight),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  SliverToBoxAdapter _buildError(ThemeData theme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Text(_error!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildContent(ThemeData theme) {
    final a = _artist!;

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stats row
              Row(
                children: [
                  if (a.genre != null) ...[
                    Chip(
                      label:
                          Text(a.genre!, style: const TextStyle(fontSize: 12)),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Icon(Icons.visibility_rounded,
                      size: 14,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.4)),
                  const SizedBox(width: 4),
                  Text(_formatNumber(a.views),
                      style: theme.textTheme.labelSmall),
                  const SizedBox(width: 12),
                  Icon(Icons.headphones_rounded,
                      size: 14,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.4)),
                  const SizedBox(width: 4),
                  Text(_formatNumber(a.listeners),
                      style: theme.textTheme.labelSmall),
                ],
              ),

              // Bio
              if (a.bio != null && a.bio!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(a.bio!,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6),
                      height: 1.5,
                    )),
              ],

              // Songs header + play all
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('Songs',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text('${a.songs.length}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5),
                      )),
                  const Spacer(),
                  if (a.songs.isNotEmpty)
                    FilledButton.tonalIcon(
                      onPressed: () => MusicPlayerHelper.playFromList(
                          context, a.songs, 0),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Play All'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: const Size(0, 34),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),

      // Songs list with artwork
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final song = a.songs[index];
            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: song.artwork,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    width: 48,
                    height: 48,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: 48,
                    height: 48,
                    color: Colors.white.withValues(alpha: 0.05),
                    child: const Icon(Icons.music_note,
                        size: 20, color: Colors.white24),
                  ),
                ),
              ),
              title: Text(song.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5),
                  )),
              trailing: const Icon(Icons.play_circle_outline_rounded,
                  size: 22),
              onTap: () => MusicPlayerHelper.playFromList(
                  context, a.songs, index),
              onLongPress: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SongDetailPage(songId: song.id),
                ),
              ),
            );
          },
          childCount: a.songs.length,
        ),
      ),

      const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
    ];
  }
}

// =============================================================================
// Shimmer bar
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
