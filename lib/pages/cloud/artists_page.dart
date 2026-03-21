import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../Routes/routes.dart';
import '../../services/music/music_models.dart';
import '../../services/music/music_repository.dart';
import 'artist_detail_page.dart';

class ArtistsPage extends StatefulWidget {
  const ArtistsPage({super.key});

  @override
  State<ArtistsPage> createState() => _ArtistsPageState();
}

class _ArtistsPageState extends State<ArtistsPage> {
  final _repo = MusicRepositoryImpl();
  final _scrollController = ScrollController();
  final List<MusicArtist> _artists = [];

  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadPage();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 200) {
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    if (_loadingMore) return;

    setState(() {
      if (_page == 1) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });

    final result = await _repo.fetchArtists(page: _page);
    if (!mounted) return;

    result.fold(
      (f) => setState(() {
        _loading = false;
        _loadingMore = false;
        if (_page == 1) _error = f.message;
      }),
      (artists) => setState(() {
        _loading = false;
        _loadingMore = false;
        if (artists.isEmpty) {
          _hasMore = false;
        } else {
          _artists.addAll(artists);
          _page++;
        }
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
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
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
        child: Text(
          'No artists found',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: _artists.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _artists.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: CachedNetworkImage(
              imageUrl: artist.image,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                width: 80,
                height: 80,
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(Icons.person,
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.2)),
              ),
              errorWidget: (_, __, ___) => Container(
                width: 80,
                height: 80,
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
      ),
    );
  }
}
