import 'dart:io';

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '/helpers/channel.dart';
import '/controllers/app_controller.dart';
import '/data/library_repository.dart';
import '/models/recognition_result.dart';
import '/pages/album_songs.dart';
import '/pages/artist_songs.dart';
import 'playlist_widget.dart';

/// Bottom sheet with song actions: Identify track, Add to playlist, etc.
class SongOptionsSheet extends StatefulWidget {
  final SongModel song;
  const SongOptionsSheet({super.key, required this.song});

  @override
  State<SongOptionsSheet> createState() => _SongOptionsSheetState();
}

class _SongOptionsSheetState extends State<SongOptionsSheet> {
  bool _identifying = false;
  bool _applying = false;
  RecognitionResult? _result;
  String? _error;

  bool get _hasArtist {
    final a = widget.song.artist;
    return a != null && a.trim().isNotEmpty && a != '<unknown>';
  }

  bool get _hasAlbum {
    final a = widget.song.album;
    return a != null && a.trim().isNotEmpty;
  }

  Future<void> _goToArtist() async {
    final artist = widget.song.artist!;
    final repo = context.read<LibraryRepository>();
    final nav = Navigator.of(context);
    final songs = await repo.watchArtistSongs(artist).first;
    if (!mounted) return;
    nav.pop();
    nav.push(
      MaterialPageRoute(
        builder: (_) => ArtistSongs(
          artistId: widget.song.artistId,
          artist: artist,
          songs: songs.length,
          albums: 0,
        ),
      ),
    );
  }

  Future<void> _goToAlbum() async {
    final album = widget.song.album!;
    final repo = context.read<LibraryRepository>();
    final nav = Navigator.of(context);
    final songs = await repo.watchAlbumSongs(album).first;
    if (!mounted) return;
    nav.pop();
    nav.push(
      MaterialPageRoute(
        builder: (_) => AlbumSongs(
          albumId: widget.song.albumId,
          album: album,
          songs: songs.length,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Song info header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                QueryArtworkWidget(
                  id: widget.song.id,
                  type: ArtworkType.AUDIO,
                  artworkHeight: 48,
                  artworkWidth: 48,
                  artworkBorder: BorderRadius.circular(8),
                  nullArtworkWidget: Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.music_note,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.song.title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.song.artist ?? 'Unknown artist',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),

          // Identify track
          if (_applying) ...[
            const ListTile(
              leading: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              ),
              title: Text("Saving tags..."),
              subtitle: Text("Writing metadata and artwork"),
            ),
          ] else if (_result != null) ...[
            _buildResultTile(theme),
          ] else if (_identifying) ...[
            const ListTile(
              leading: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              ),
              title: Text("Identifying track..."),
              subtitle: Text("Fingerprinting and searching databases"),
            ),
          ] else ...[
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text("Identify track"),
              subtitle: _error != null
                  ? Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    )
                  : const Text("Recognize song using audio fingerprint"),
              onTap: _identifyTrack,
            ),
          ],

          const Divider(height: 1, indent: 16, endIndent: 16),

          // Add to playlist
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text("Add to playlist"),
            onTap: () {
              Navigator.pop(context);
              showModalBottomSheet(
                context: context,
                builder: (_) => BottomSheet(
                  onClosing: () {},
                  builder: (_) => PlaylistWidget(
                    audioId: widget.song.id,
                    song: widget.song.title,
                  ),
                ),
              );
            },
          ),

          // Go to artist
          if (_hasArtist)
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text("Go to artist"),
              subtitle: Text(
                widget.song.artist!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: _goToArtist,
            ),

          // Go to album
          if (_hasAlbum)
            ListTile(
              leading: const Icon(Icons.album_outlined),
              title: const Text("Go to album"),
              subtitle: Text(
                widget.song.album!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: _goToAlbum,
            ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _identifyTrack() async {
    setState(() {
      _identifying = true;
      _error = null;
    });

    try {
      final controller = AppController.instance;
      final isCloud = widget.song.data.startsWith('http');

      // For cloud files, use the locally cached audio file for fingerprinting
      String? fingerprintPath;
      if (isCloud) {
        final fileId = widget.song.id.toString();
        if (controller.cloudCache.isCached(fileId)) {
          fingerprintPath = controller.cloudCache.cacheFile(fileId).path;
        } else {
          if (!mounted) return;
          setState(() {
            _identifying = false;
            _error = "Cloud track not cached — play it first";
          });
          return;
        }
      }

      final result = await controller.fingerprintService.identifySong(
        widget.song,
        fingerprintPath: fingerprintPath,
      );

      if (!mounted) return;

      if (result == null || !result.hasUsefulData) {
        setState(() {
          _identifying = false;
          _error = "Could not identify this track";
        });
      } else {
        setState(() {
          _identifying = false;
          _result = result;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _identifying = false;
        _error = "Identification failed";
      });
    }
  }

  Widget _buildResultTile(ThemeData theme) {
    final r = _result!;
    return Column(
      children: [
        ListTile(
          leading: Icon(Icons.check_circle, color: theme.colorScheme.primary),
          title: Text(r.title ?? 'Unknown'),
          subtitle: Text(
            [
              if (r.artist != null) r.artist!,
              if (r.album != null) r.album!,
              if (r.year != null) r.year!,
            ].join(' - '),
          ),
          trailing: Text(
            '${(r.score * 100).round()}%',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _applyTags,
                  child: const Text("Apply tags"),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Dismiss"),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _applyTags() async {
    if (_result == null) return;

    setState(() => _applying = true);

    final controller = AppController.instance;
    final isCloud = widget.song.data.startsWith('http');

    try {
      // Write tags directly from the already-identified result
      final tagMap = _result!.toTagMap();
      if (tagMap.isEmpty) {
        if (!mounted) return;
        setState(() => _applying = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("No tags to write")));
        return;
      }

      // Fetch cover art if available
      String? artworkPath;
      if (_result!.musicBrainzReleaseId != null) {
        artworkPath = await controller.fingerprintService.fetchCoverArt(
          _result!.musicBrainzReleaseId!,
        );
      }

      // Write tags to file (local files only — can't write to remote URLs)
      if (!isCloud) {
        final ok = await Channel.writeTags(
          widget.song.data,
          tagMap,
          artworkPath: artworkPath,
        );

        if (!ok) {
          // Clean up temp artwork on failure
          if (artworkPath != null) {
            try {
              File(artworkPath).deleteSync();
            } catch (_) {}
          }
          if (!mounted) return;
          setState(() => _applying = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Failed to write tags")));
          return;
        }

        // Trigger MediaStore re-scan
        await Channel.scanMediaFile(widget.song.data);
      }

      // Update in-memory state + save artwork to UI cache
      await controller.updateSongMetadata(
        widget.song,
        _result!,
        newArtworkPath: artworkPath,
      );

      // Clean up temp artwork after it's been copied to cache
      if (artworkPath != null) {
        try {
          File(artworkPath).deleteSync();
        } catch (_) {}
      }

      if (!mounted) return;

      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Tags and artwork updated")));
    } catch (e) {
      if (!mounted) return;
      setState(() => _applying = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to write tags")));
    }
  }
}
