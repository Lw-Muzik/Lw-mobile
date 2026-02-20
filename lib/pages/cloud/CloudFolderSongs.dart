import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:id3tag/id3tag.dart';
import '/exports/exports.dart';
import '/Routes/routes.dart';
import '../../controllers/AppController.dart';
import '../../models/cloud_file.dart';
import '../../player/PlayerUI.dart';
import '../../widgets/BottomPlayer.dart';
import '../../widgets/song_tile.dart';

class CloudFolderSongs extends StatefulWidget {
  final String folderName;
  final List<CloudFile> files;
  final CloudProvider provider;

  const CloudFolderSongs({
    super.key,
    required this.folderName,
    required this.files,
    required this.provider,
  });

  @override
  State<CloudFolderSongs> createState() => _CloudFolderSongsState();
}

class _CloudFolderSongsState extends State<CloudFolderSongs> {
  List<SongModel>? _songModels;
  List<String>? _streamUrls;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolveStreamUrls();
  }

  Future<void> _resolveStreamUrls() async {
    final controller = Provider.of<AppController>(context, listen: false);

    try {
      final models = <SongModel>[];
      final urls = <String>[];
      for (final file in widget.files) {
        String? streamUrl;
        if (file.provider == CloudProvider.googleDrive) {
          streamUrl = controller.googleDriveService.getStreamUrl(file.fileId);
        } else {
          streamUrl =
              await controller.dropboxService.getTemporaryLink(file.fileId);
        }
        if (streamUrl != null) {
          models.add(file.toSongModel(streamUrl));
          urls.add(streamUrl);
        }
      }
      if (mounted) {
        setState(() {
          _songModels = models;
          _streamUrls = urls;
          _loading = false;
        });
        // Start background metadata extraction
        _extractMetadataInBackground();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _extractMetadataInBackground() async {
    if (_songModels == null || _streamUrls == null) return;

    final controller = Provider.of<AppController>(context, listen: false);
    final tempDir = await getTemporaryDirectory();

    for (int i = 0; i < widget.files.length && i < _songModels!.length; i++) {
      if (!mounted) break;

      final file = widget.files[i];
      final streamUrl = _streamUrls![i];
      final songId = file.fileId.hashCode.abs();
      final artPath = '${tempDir.path}/cloud_art_$songId.png';
      final metaCachePath = '${tempDir.path}/cloud_meta_$songId.done';

      // Skip if metadata already extracted in a previous session
      if (File(metaCachePath).existsSync()) {
        // Artwork was already saved — just refresh the tile if art exists
        if (File(artPath).existsSync() && mounted) {
          setState(() {});
        }
        continue;
      }

      try {
        // Build headers (Google Drive needs auth, Dropbox temp links don't)
        final headers = <String, String>{};
        if (file.provider == CloudProvider.googleDrive) {
          headers.addAll(await controller.cloudAuth.getGoogleAuthHeaders());
        }
        // Download only the first 512KB (enough for ID3v2 header + artwork)
        headers['Range'] = 'bytes=0-524287';

        final response = await http.get(Uri.parse(streamUrl), headers: headers);
        if (response.statusCode != 200 && response.statusCode != 206) continue;

        // Save partial download to temp file for ID3 parsing
        final partialPath = '${tempDir.path}/cloud_partial_$songId.tmp';
        final partialFile = File(partialPath);
        await partialFile.writeAsBytes(response.bodyBytes);

        // Parse ID3 tags
        String? title, artist, album;
        bool hasArtwork = false;

        try {
          final parser = ID3TagReader.path(partialPath);
          final tag = await parser.readTag();

          // Extract text metadata using framesWithName
          final titleFrames = tag.framesWithName('TIT2');
          if (titleFrames.isNotEmpty && titleFrames.first is TextInformation) {
            title = (titleFrames.first as TextInformation).value;
          }
          final artistFrames = tag.framesWithName('TPE1');
          if (artistFrames.isNotEmpty && artistFrames.first is TextInformation) {
            artist = (artistFrames.first as TextInformation).value;
          }
          final albumFrames = tag.framesWithName('TALB');
          if (albumFrames.isNotEmpty && albumFrames.first is TextInformation) {
            album = (albumFrames.first as TextInformation).value;
          }

          // Extract and save artwork
          if (tag.pictures.isNotEmpty) {
            await File(artPath).writeAsBytes(tag.pictures.first.imageData);
            hasArtwork = true;
          }
        } catch (_) {
          // ID3 parsing failed (truncated file, no tags, etc.) — continue
        }

        // Cleanup partial file
        if (partialFile.existsSync()) partialFile.deleteSync();

        // Mark metadata as extracted so we skip next time
        await File(metaCachePath).writeAsString('done');

        // Update song model if metadata was found
        if (mounted && (title != null || artist != null || hasArtwork)) {
          final updatedFile = CloudFile(
            provider: file.provider,
            fileId: file.fileId,
            name: file.name,
            folderPath: file.folderPath,
            size: file.size,
            mimeType: file.mimeType,
            thumbnailUrl: file.thumbnailUrl,
            modifiedDate: file.modifiedDate,
            trackTitle: title ?? file.trackTitle,
            trackArtist: artist ?? file.trackArtist,
            albumName: album ?? file.albumName,
            durationMs: file.durationMs,
          );
          setState(() {
            _songModels![i] = updatedFile.toSongModel(streamUrl);
          });
        }
      } catch (_) {
        // Failed for this file — continue with next
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, _) => NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            forceMaterialTransparency: controller.isFancy,
            expandedHeight: 160,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding:
                  const EdgeInsets.only(left: 56, bottom: 16, right: 16),
              title: Text(
                widget.folderName,
                style: const TextStyle(fontSize: 18),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.15),
                      Theme.of(context).scaffoldBackgroundColor,
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    widget.provider == CloudProvider.googleDrive
                        ? Icons.cloud_rounded
                        : Icons.cloud_circle_rounded,
                    size: 48,
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ),
        ],
        body: _buildBody(controller),
      ),
    );
  }

  Widget _buildBody(AppController controller) {
    return StreamBuilder<bool>(
      stream: controller.handler.player.playingStream,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data ?? false;

        return Scaffold(
          backgroundColor: controller.isFancy
              ? Colors.transparent
              : Theme.of(context).scaffoldBackgroundColor,
          body: _buildContent(controller),
          bottomNavigationBar:
              isPlaying ? BottomPlayer(controller: controller) : null,
        );
      },
    );
  }

  Widget _buildContent(AppController controller) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text('Failed to load songs',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _resolveStreamUrls();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final songs = _songModels ?? [];
    return SongListView(
      songs: songs,
      controller: controller,
      onTap: (song, index) {
        controller.playSongFromList(songs, index);
        Routes.routeTo(const Player(), context);
      },
    );
  }
}
