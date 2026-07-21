import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../Routes/routes.dart';
import '../../controllers/AppController.dart';
import '../../services/music/music_models.dart';
import '../../services/music/music_repository.dart';

class SongDetailPage extends StatefulWidget {
  final String songId;
  const SongDetailPage({super.key, required this.songId});

  @override
  State<SongDetailPage> createState() => _SongDetailPageState();
}

class _SongDetailPageState extends State<SongDetailPage> {
  final _repo = MusicRepositoryImpl();
  MusicSongDetail? _detail;
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
    final result = await _repo.fetchSongDetail(widget.songId);
    if (!mounted) return;
    result.fold(
      (f) => setState(() {
        _loading = false;
        _error = f.message;
      }),
      (detail) => setState(() {
        _loading = false;
        _detail = detail;
      }),
    );
  }

  void _play() {
    if (_detail == null || _detail!.audioUrls.isEmpty) return;
    final controller = context.read<AppController>();
    final audioUrl = _detail!.audioUrls.first;
    final songModel = SongModel({
      '_id': audioUrl.hashCode.abs(),
      '_data': audioUrl,
      'title': _detail!.title,
      'artist': _detail!.artist,
      'album': _detail!.artwork,
      'duration': 0,
      '_display_name': '${_detail!.title}.mp3',
      '_display_name_wo_ext': _detail!.title,
      '_size': 0,
      'file_extension': 'mp3',
      'is_music': true,
    });
    controller.playSongFromList([songModel], 0);
    Routes.playerTo(context);
  }

  String _formatDuration(String? iso) {
    if (iso == null) return '';
    final match =
        RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?').firstMatch(iso);
    if (match == null) return '';
    final h = int.tryParse(match.group(1) ?? '') ?? 0;
    final m = int.tryParse(match.group(2) ?? '') ?? 0;
    final s = int.tryParse(match.group(3) ?? '') ?? 0;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s}s';
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
      appBar: AppBar(title: Text(_detail?.title ?? 'Song')),
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
    final d = _detail!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Artwork + info
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: d.artwork,
                width: 140,
                height: 140,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: 140,
                  height: 140,
                  color: Colors.white.withValues(alpha: 0.05),
                  child: const Icon(Icons.music_note,
                      size: 40, color: Colors.white24),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.title,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(d.artist,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      )),
                  const SizedBox(height: 12),
                  if (d.duration != null)
                    _InfoChip(
                        icon: Icons.timer_outlined,
                        label: _formatDuration(d.duration)),
                  if (d.plays != null)
                    _InfoChip(
                        icon: Icons.play_arrow_rounded,
                        label: '${_formatNumber(d.plays)} plays'),
                  if (d.downloads != null)
                    _InfoChip(
                        icon: Icons.download_rounded,
                        label: '${_formatNumber(d.downloads)} downloads'),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Play button
        if (d.audioUrls.isNotEmpty)
          FilledButton.icon(
            onPressed: _play,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Play'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),

        if (d.audioUrls.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.music_off_rounded,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.4)),
                const SizedBox(width: 12),
                Text('Audio not available',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5),
                    )),
              ],
            ),
          ),

        // Related songs
        if (d.relatedSongs.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Related Songs',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...List.generate(d.relatedSongs.length, (index) {
            final song = d.relatedSongs[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: song.artwork,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 44,
                    height: 44,
                    color: Colors.white.withValues(alpha: 0.05),
                    child: const Icon(Icons.music_note,
                        size: 18, color: Colors.white24),
                  ),
                ),
              ),
              title: Text(song.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(song.artist,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.play_circle_outline_rounded,
                  size: 22),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SongDetailPage(songId: song.id),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 14,
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.4)),
          const SizedBox(width: 4),
          Text(label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface
                    .withValues(alpha: 0.5),
              )),
        ],
      ),
    );
  }
}
