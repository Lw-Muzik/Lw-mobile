import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../../Routes/routes.dart';
import '../../controllers/AppController.dart';
import '../../player/player_ui.dart';
import 'music_models.dart';
import 'music_repository.dart';

/// Resolves audio URLs for MusicSong items and plays them.
///
/// Song list endpoints return page URLs, not streamable audio.
/// This helper fetches the song detail to get the actual MP3 URL,
/// plays the tapped song instantly, then resolves remaining songs
/// in background to build the full queue for continuous playback.
class MusicPlayerHelper {
  static final _repo = MusicRepositoryImpl();

  /// Plays a list of songs starting at [index].
  /// Resolves the tapped song immediately, starts playback,
  /// then resolves the rest in background to build the queue.
  static Future<void> playFromList(
    BuildContext context,
    List<MusicSong> songs,
    int index,
  ) async {
    if (songs.isEmpty) return;

    final tapped = songs[index];
    final audioUrl = await _resolveWithOverlay(context, tapped);
    if (audioUrl == null || !context.mounted) return;

    final controller = context.read<AppController>();

    // Play tapped song immediately
    final tappedModel = _toSongModel(tapped, audioUrl);
    controller.playSongFromList([tappedModel], 0);
    Routes.routeTo(const Player(), context);

    // Background: resolve all other songs and rebuild queue
    if (songs.length > 1) {
      _resolveQueueInBackground(controller, songs, index, audioUrl);
    }
  }

  /// Resolves all songs concurrently (5 at a time) and rebuilds the player queue.
  static Future<void> _resolveQueueInBackground(
    AppController controller,
    List<MusicSong> songs,
    int tappedIndex,
    String tappedAudioUrl,
  ) async {
    final resolved = <int, String>{tappedIndex: tappedAudioUrl};
    const concurrency = 5;

    // Process in batches of [concurrency]
    for (int batch = 0; batch < songs.length; batch += concurrency) {
      final futures = <Future>[];
      for (int i = batch;
          i < (batch + concurrency).clamp(0, songs.length);
          i++) {
        if (i == tappedIndex) continue;
        futures.add(_repo.fetchSongDetail(songs[i].id).then((result) {
          result.fold((_) {}, (detail) {
            if (detail.audioUrls.isNotEmpty) {
              resolved[i] = detail.audioUrls.first;
            }
          });
        }));
      }
      await Future.wait(futures);
    }

    // Build full queue preserving original order
    final queue = <SongModel>[];
    final indexMap = <int, int>{}; // original index → queue index
    for (int i = 0; i < songs.length; i++) {
      if (resolved.containsKey(i)) {
        indexMap[i] = queue.length;
        queue.add(_toSongModel(songs[i], resolved[i]!));
      }
    }

    if (queue.length <= 1) return;

    // Find the new index of the tapped song in the queue
    final newIndex = indexMap[tappedIndex] ?? 0;
    controller.playSongFromList(queue, newIndex);
  }

  /// Shows a loading overlay, fetches audio URL, removes overlay.
  static Future<String?> _resolveWithOverlay(
    BuildContext context,
    MusicSong song,
  ) async {
    final overlay = OverlayEntry(
      builder: (_) => _LoadingOverlay(songTitle: song.title),
    );
    Overlay.of(context).insert(overlay);

    try {
      final result = await _repo.fetchSongDetail(song.id);
      overlay.remove();

      return result.fold(
        (failure) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to load: ${failure.message}'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return null;
        },
        (detail) {
          if (detail.audioUrls.isEmpty) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No audio available for this song'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
            return null;
          }
          return detail.audioUrls.first;
        },
      );
    } catch (e) {
      overlay.remove();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), behavior: SnackBarBehavior.floating),
        );
      }
      return null;
    }
  }

  static SongModel _toSongModel(MusicSong song, String audioUrl) {
    return SongModel({
      '_id': audioUrl.hashCode.abs(),
      '_data': audioUrl,
      'title': song.title,
      'artist': song.artist,
      'album': song.artwork,
      'duration': 0,
      '_display_name': '${song.title}.mp3',
      '_display_name_wo_ext': song.title,
      '_size': 0,
      'file_extension': 'mp3',
      'is_music': true,
    });
  }
}

class _LoadingOverlay extends StatelessWidget {
  final String songTitle;
  const _LoadingOverlay({required this.songTitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 14),
              Text(songTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Loading...',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
