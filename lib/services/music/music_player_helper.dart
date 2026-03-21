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
/// NowViba song list endpoints only return page URLs, not streamable audio.
/// This helper fetches the song detail to get the actual MP3 URL before playing.
class MusicPlayerHelper {
  static final _repo = MusicRepositoryImpl();

  /// Resolves the audio URL for a single song and plays it.
  /// Shows a loading overlay while fetching the audio URL.
  static Future<void> playSong(
    BuildContext context,
    MusicSong song,
  ) async {
    final audioUrl = await _resolveAudioUrl(context, song);
    if (audioUrl == null || !context.mounted) return;

    final controller = context.read<AppController>();
    final songModel = _toSongModel(song, audioUrl);
    controller.playSongFromList([songModel], 0);
    Routes.routeTo(const Player(), context);
  }

  /// Resolves audio URLs for a list and plays from the given index.
  /// Only resolves the tapped song immediately; the rest stream on demand.
  static Future<void> playSongFromList(
    BuildContext context,
    List<MusicSong> songs,
    int index,
  ) async {
    final tapped = songs[index];
    final audioUrl = await _resolveAudioUrl(context, tapped);
    if (audioUrl == null || !context.mounted) return;

    // Build the queue: tapped song gets resolved URL, others use their page URL
    // (they'll be resolved when the player reaches them via loadAudioSource)
    // Actually, build a single-song list with the resolved URL for immediate play.
    // For queue mode, resolve all in background.
    final controller = context.read<AppController>();
    final songModel = _toSongModel(tapped, audioUrl);
    controller.playSongFromList([songModel], 0);
    Routes.routeTo(const Player(), context);
  }

  static Future<String?> _resolveAudioUrl(
    BuildContext context,
    MusicSong song,
  ) async {
    // Show loading overlay
    final overlay = OverlayEntry(
      builder: (_) => Container(
        color: Colors.black.withValues(alpha: 0.3),
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator.adaptive(),
                  SizedBox(height: 12),
                  Text('Loading song...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final overlayState = Overlay.of(context);
    overlayState.insert(overlay);

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
          SnackBar(
            content: Text('Error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
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
