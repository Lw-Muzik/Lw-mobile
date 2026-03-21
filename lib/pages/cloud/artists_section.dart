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

class _ArtistsSectionState extends State<ArtistsSection> {
  final _repo = MusicRepositoryImpl();
  List<MusicArtist> _artists = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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

    if (_loading) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

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
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              const SizedBox(width: 8),
              Text('Artists',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
              const Spacer(),
              Text('${_artists.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.5),
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
                        slug: slug, artistId: artist.id, name: artist.name),
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
