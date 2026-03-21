import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../Routes/routes.dart';
import '../../services/music/music_models.dart';
import '../../services/music/music_player_helper.dart';
import '../../services/music/music_repository.dart';
import 'song_detail_page.dart';

class PopularSection extends StatefulWidget {
  const PopularSection({super.key});

  @override
  State<PopularSection> createState() => _PopularSectionState();
}

class _PopularSectionState extends State<PopularSection> {
  final _repo = MusicRepositoryImpl();
  List<MusicSong> _songs = [];
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
    final result = await _repo.fetchPopular();
    if (!mounted) return;
    result.fold(
      (f) => setState(() {
        _loading = false;
        _error = f.message;
      }),
      (songs) => setState(() {
        _loading = false;
        _songs = songs;
      }),
    );
  }

  void _playSong(MusicSong song) {
    MusicPlayerHelper.playSong(context, song);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    if (_error != null) {
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
              Text('${_songs.length} songs',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  )),
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
                onTap: () => _playSong(song),
                onLongPress: () =>
                    Routes.routeTo(SongDetailPage(songId: song.id), context),
              );
            },
          ),
        ),

        const SizedBox(height: 8),

        // Full list
        ...List.generate(
          _songs.length.clamp(0, 50),
          (index) {
            final song = _songs[index];
            return _PopularTile(
              song: song,
              rank: index + 1,
              onTap: () => _playSong(song),
              onLongPress: () =>
                  Routes.routeTo(SongDetailPage(songId: song.id), context),
            );
          },
        ),
      ],
    );
  }
}

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
                      child: const Icon(Icons.music_note,
                          color: Colors.white24),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.white.withValues(alpha: 0.05),
                      child: const Icon(Icons.music_note,
                          color: Colors.white24),
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
                  fontWeight:
                      rank <= 3 ? FontWeight.w700 : FontWeight.w500,
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
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      )),
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
                color:
                    theme.colorScheme.onSurface.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }
}
