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

class _PopularPageState extends State<PopularPage> {
  final _repo = MusicRepositoryImpl();
  final _scrollController = ScrollController();
  final List<MusicSong> _songs = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
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
    if (_hasMore &&
        !_loadingMore &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300) {
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    if (_loadingMore) return;
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
      }),
      (songs) => setState(() {
        _loading = false;
        _loadingMore = false;
        _songs.addAll(songs);
        _hasMore = songs.length >= 50;
        _offset += 55;
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
                child: Text('${_songs.length} songs',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    )),
              ),
            ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
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

    if (_songs.isEmpty) {
      return Center(
        child: Text('No songs found',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            )),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      itemCount: _songs.length + (_loadingMore || _hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _songs.length) {
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Center(
              child: TextButton(
                onPressed: _loadPage,
                child: const Text('Load more'),
              ),
            ),
          );
        }

        final song = _songs[index];
        final rank = index + 1;
        return _PopularTile(
          song: song,
          rank: rank,
          onTap: () => MusicPlayerHelper.playFromList(context, _songs, index),
          onLongPress: () =>
              Routes.routeTo(SongDetailPage(songId: song.id), context),
        );
      },
    );
  }
}

// =============================================================================
// Song tile widget (matches PopularSection._PopularTile)
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
