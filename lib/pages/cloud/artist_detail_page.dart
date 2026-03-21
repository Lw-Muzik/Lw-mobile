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

  const ArtistDetailPage({
    super.key,
    required this.slug,
    required this.artistId,
    required this.name,
  });

  @override
  State<ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends State<ArtistDetailPage> {
  final _repo = MusicRepositoryImpl();
  MusicArtistDetail? _artist;
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
    final result =
        await _repo.fetchArtistDetail(widget.slug, widget.artistId);
    if (!mounted) return;
    result.fold(
      (f) => setState(() {
        _loading = false;
        _error = f.message;
      }),
      (artist) => setState(() {
        _loading = false;
        _artist = artist;
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
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                )
              : _buildContent(theme),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final a = _artist!;

    return CustomScrollView(
      slivers: [
        // Collapsible header with artist image
        SliverAppBar(
          expandedHeight: 260,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            title: Text(a.name,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            background: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: a.image,
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
                        label: Text(a.genre!,
                            style: const TextStyle(fontSize: 12)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
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

                // Songs header
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text('Songs',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('${a.songs.length}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        )),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),

        // Songs list
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
                trailing: const Icon(
                    Icons.play_circle_outline_rounded,
                    size: 22),
                onTap: () => MusicPlayerHelper.playSong(context, song),
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
      ],
    );
  }
}
