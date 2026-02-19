import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/pages/ArtistSongs.dart';
import 'package:eq_app/widgets/ArtworkWidget.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../controllers/AppController.dart';
import '../../pages/AlbumSongs.dart';
import '../../widgets/PlayListWidget.dart';
import 'ArtworkFetch.dart';

class TrackInfoWidget extends StatelessWidget {
  final AppController controller;
  const TrackInfoWidget({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final song = controller.songs[controller.songId];
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Routes.pop(context),
        behavior: HitTestBehavior.opaque,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, // absorb taps on the sheet itself
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header with artwork + song info
                      _TrackHeader(song: song),
                      const Divider(
                        color: Colors.white10,
                        height: 1,
                        indent: 20,
                        endIndent: 20,
                      ),
                      // Action list
                      _ActionTile(
                        icon: Icons.playlist_add_rounded,
                        label: 'Add to Playlist',
                        onTap: () {
                          Routes.pop(context);
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            builder: (_) => BottomSheet(
                              backgroundColor: Colors.transparent,
                              builder: (_) => PlaylistWidget(
                                audioId: song.id,
                                song: song.title,
                              ),
                              onClosing: () {},
                            ),
                          );
                        },
                      ),
                      _ActionTile(
                        icon: Icons.person_outline_rounded,
                        label: 'Go to Artist',
                        subtitle: song.artist ?? 'Unknown Artist',
                        onTap: () {
                          Routes.pop(context);
                          Routes.routeTo(
                            ArtistSongs(
                              artistId: song.artistId,
                              artist: song.artist ?? 'Unknown Artist',
                              songs: 0,
                              albums: 0,
                            ),
                            context,
                          );
                        },
                      ),
                      _ActionTile(
                        icon: Icons.album_rounded,
                        label: 'Go to Album',
                        subtitle: song.album ?? 'Unknown Album',
                        onTap: () {
                          Routes.pop(context);
                          Routes.routeTo(
                            AlbumSongs(
                              albumId: song.albumId,
                              album: song.album ?? 'Unknown Album',
                              songs: 0,
                            ),
                            context,
                          );
                        },
                      ),
                      _ActionTile(
                        icon: Icons.image_outlined,
                        label: 'Find Artwork',
                        onTap: () {
                          Routes.pop(context);
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            builder: (_) => BottomSheet(
                              backgroundColor: Colors.transparent,
                              builder: (_) => ArtworkFetch(
                                path: song.data,
                                title: song.title,
                                artist: song.artist ?? '',
                              ),
                              onClosing: () {},
                            ),
                          );
                        },
                      ),
                      SizedBox(height: bottomPadding + 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Top section: artwork + title, artist, album.
class _TrackHeader extends StatelessWidget {
  final SongModel song;
  const _TrackHeader({required this.song});

  String _formatDuration(int? ms) {
    if (ms == null) return '--:--';
    final d = Duration(milliseconds: ms);
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        children: [
          // Artwork
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 80,
              height: 80,
              child: ArtworkWidget(
                width: 80,
                height: 80,
                quality: 100,
                size: 500,
                songId: song.id,
                type: ArtworkType.AUDIO,
                path: song.data,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Text info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  song.artist ?? 'Unknown Artist',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      song.album ?? 'Unknown Album',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white30, fontSize: 12),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 3,
                      height: 3,
                      decoration: const BoxDecoration(
                        color: Colors.white24,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatDuration(song.duration),
                      style:
                          const TextStyle(color: Colors.white30, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Single action row in the info sheet.
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white70, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white24,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
