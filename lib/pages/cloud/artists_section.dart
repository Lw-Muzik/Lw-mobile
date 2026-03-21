import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../Routes/routes.dart';
import '../../services/music/music_models.dart';
import '../../services/music/music_repository.dart';
import 'artist_detail_page.dart';

class ArtistsSection extends StatefulWidget {
  const ArtistsSection({super.key});

  @override
  State<ArtistsSection> createState() => _ArtistsSectionState();
}

class _ArtistsSectionState extends State<ArtistsSection>
    with SingleTickerProviderStateMixin {
  final _repo = MusicRepositoryImpl();
  List<MusicArtist> _artists = [];
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
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _repo.fetchArtists();
    if (!mounted) return;
    result.fold(
      (f) => setState(() {
        _loading = false;
        _error = f.message;
      }),
      (artists) => setState(() {
        _loading = false;
        _artists = artists;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) return _ArtistsSkeleton(controller: _shimmerCtrl);
    if (_error != null || _artists.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            children: [
              Icon(Icons.people_rounded,
                  size: 18,
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              const SizedBox(width: 8),
              Text('Artists',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${_artists.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5),
                  )),
            ],
          ),
        ),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _artists.length,
            itemBuilder: (context, index) {
              final artist = _artists[index];
              return _ArtistChip(
                artist: artist,
                onTap: () {
                  final slug = artist.name.replaceAll(' ', '-');
                  Routes.routeTo(
                    ArtistDetailPage(
                        slug: slug,
                        artistId: artist.id,
                        name: artist.name,
                        imageUrl: artist.image),
                    context,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Skeleton
// =============================================================================

class _ArtistsSkeleton extends StatelessWidget {
  final AnimationController controller;
  const _ArtistsSkeleton({required this.controller});

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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: _ShimmerCircleBar(
                  width: 80, height: 18, offset: controller.value,
                  base: base, highlight: highlight),
            ),
            SizedBox(
              height: 110,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: 5,
                itemBuilder: (_, i) {
                  final off = (controller.value + i * 0.12) % 1.0;
                  return Container(
                    width: 80,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [base, highlight, base],
                              stops: const [0.0, 0.5, 1.0],
                              begin: Alignment(-1.0 + 2.0 * off, 0),
                              end: Alignment(1.0 + 2.0 * off, 0),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _ShimmerCircleBar(
                            width: 54, height: 10, offset: off,
                            base: base, highlight: highlight),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ShimmerCircleBar extends StatelessWidget {
  final double width, height, offset;
  final Color base, highlight;
  const _ShimmerCircleBar({
    required this.width, required this.height, required this.offset,
    required this.base, required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
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

// =============================================================================
// Artist chip
// =============================================================================

class _ArtistChip extends StatelessWidget {
  final MusicArtist artist;
  final VoidCallback onTap;

  const _ArtistChip({required this.artist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            ClipOval(
              child: CachedNetworkImage(
                imageUrl: artist.image,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 64,
                  height: 64,
                  color: Colors.white.withValues(alpha: 0.05),
                  child: const Icon(Icons.person, color: Colors.white24),
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 64,
                  height: 64,
                  color: Colors.white.withValues(alpha: 0.05),
                  child: const Icon(Icons.person, color: Colors.white24),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              artist.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
