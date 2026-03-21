import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../Routes/routes.dart';
import '../../services/music/music_models.dart';
import '../../services/music/music_player_helper.dart';
import '../../services/music/music_repository.dart';
import 'song_detail_page.dart';

class MusicSearchPage extends StatefulWidget {
  const MusicSearchPage({super.key});

  @override
  State<MusicSearchPage> createState() => _MusicSearchPageState();
}

class _MusicSearchPageState extends State<MusicSearchPage> {
  final _repo = MusicRepositoryImpl();
  final _controller = TextEditingController();
  Timer? _debounce;
  List<MusicSong> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _repo.search(query.trim());
    if (!mounted) return;
    result.fold(
      (f) => setState(() {
        _loading = false;
        _error = f.message;
      }),
      (songs) => setState(() {
        _loading = false;
        _results = songs;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: 'Search songs...',
            border: InputBorder.none,
            hintStyle: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, size: 20),
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 40,
                color: theme.colorScheme.error.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            Text(_error!, style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    if (_controller.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded,
                size: 56,
                color:
                    theme.colorScheme.onSurface.withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            Text('Search for songs',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface
                      .withValues(alpha: 0.4),
                )),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Text('No results found',
            style: theme.textTheme.bodyMedium?.copyWith(
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.4),
            )),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final song = _results[index];
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
                color:
                    theme.colorScheme.onSurface.withValues(alpha: 0.5),
              )),
          trailing: IconButton(
            icon: const Icon(Icons.info_outline_rounded, size: 20),
            onPressed: () =>
                Routes.routeTo(SongDetailPage(songId: song.id), context),
          ),
          onTap: () => MusicPlayerHelper.playSong(context, song),
        );
      },
    );
  }
}
