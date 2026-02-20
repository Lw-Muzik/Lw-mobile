import 'dart:io';
import 'dart:math' as math;

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

class _CloudFolderSongsState extends State<CloudFolderSongs>
    with SingleTickerProviderStateMixin {
  List<SongModel>? _songModels;
  List<String>? _streamUrls;
  bool _loading = true;
  String? _error;
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _resolveStreamUrls();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _resolveStreamUrls() async {
    final controller = Provider.of<AppController>(context, listen: false);

    // Reload files from cache to pick up any preloaded metadata.
    final cachedList =
        controller.cloudCache.loadFileList(widget.provider);
    final cachedMap = cachedList != null
        ? {for (final f in cachedList) f.fileId: f}
        : <String, CloudFile>{};

    try {
      final models = <SongModel>[];
      final urls = <String>[];
      for (final file in widget.files) {
        // Prefer cached version — may have preloaded ID3 metadata.
        final enriched = cachedMap[file.fileId] ?? file;
        String? streamUrl;
        if (enriched.provider == CloudProvider.googleDrive) {
          streamUrl =
              controller.googleDriveService.getStreamUrl(enriched.fileId);
        } else {
          streamUrl =
              await controller.dropboxService.getTemporaryLink(enriched.fileId);
        }
        if (streamUrl != null) {
          models.add(enriched.toSongModel(streamUrl));
          urls.add(streamUrl);
        }
      }
      if (mounted) {
        setState(() {
          _songModels = models;
          _streamUrls = urls;
          _loading = false;
        });
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

      if (File(metaCachePath).existsSync()) {
        if (File(artPath).existsSync() && mounted) {
          setState(() {});
        }
        continue;
      }

      try {
        final headers = <String, String>{};
        if (file.provider == CloudProvider.googleDrive) {
          headers.addAll(await controller.cloudAuth.getGoogleAuthHeaders());
        }
        headers['Range'] = 'bytes=0-524287';

        final response = await http.get(Uri.parse(streamUrl), headers: headers);
        if (response.statusCode != 200 && response.statusCode != 206) continue;

        final partialPath = '${tempDir.path}/cloud_partial_$songId.tmp';
        final partialFile = File(partialPath);
        await partialFile.writeAsBytes(response.bodyBytes);

        String? title, artist, album;
        bool hasArtwork = false;

        try {
          final parser = ID3TagReader.path(partialPath);
          final tag = await parser.readTag();

          final titleFrames = tag.framesWithName('TIT2');
          if (titleFrames.isNotEmpty && titleFrames.first is TextInformation) {
            title = (titleFrames.first as TextInformation).value;
          }
          final artistFrames = tag.framesWithName('TPE1');
          if (artistFrames.isNotEmpty &&
              artistFrames.first is TextInformation) {
            artist = (artistFrames.first as TextInformation).value;
          }
          final albumFrames = tag.framesWithName('TALB');
          if (albumFrames.isNotEmpty &&
              albumFrames.first is TextInformation) {
            album = (albumFrames.first as TextInformation).value;
          }

          if (tag.pictures.isNotEmpty) {
            await File(artPath).writeAsBytes(tag.pictures.first.imageData);
            hasArtwork = true;
          }
        } catch (_) {}

        if (partialFile.existsSync()) partialFile.deleteSync();
        await File(metaCachePath).writeAsString('done');

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
          controller.cloudCache.updateFileMetadata(file.provider, updatedFile);
          setState(() {
            _songModels![i] = updatedFile.toSongModel(streamUrl);
          });
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, _) => NestedScrollView(
        headerSliverBuilder: (context, _) => [
          _buildAppBar(context, controller),
        ],
        body: _buildBody(controller),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, AppController controller) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final totalSize =
        widget.files.fold<int>(0, (sum, f) => sum + f.size);
    final songCount = widget.files.length;

    return SliverAppBar(
      forceMaterialTransparency: controller.isFancy,
      expandedHeight: 200,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: EdgeInsets.zero,
        expandedTitleScale: 1.0,
        title: const SizedBox.shrink(),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.18),
                accent.withValues(alpha: 0.06),
                theme.scaffoldBackgroundColor,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Provider badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.provider == CloudProvider.googleDrive
                              ? Icons.cloud_rounded
                              : Icons.cloud_circle_rounded,
                          size: 14,
                          color: accent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.provider == CloudProvider.googleDrive
                              ? 'Google Drive'
                              : 'Dropbox',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Folder name
                  Text(
                    widget.folderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Stats row
                  Row(
                    children: [
                      Text(
                        '$songCount ${songCount == 1 ? 'song' : 'songs'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Text(
                        _formatBytes(totalSize),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      const Spacer(),
                      // Shuffle play button
                      if (!_loading && _songModels != null)
                        FilledButton.tonalIcon(
                          onPressed: () {
                            final songs = _songModels!;
                            if (songs.isEmpty) return;
                            final randomIndex =
                                math.Random().nextInt(songs.length);
                            final controller = Provider.of<AppController>(
                                context,
                                listen: false);
                            controller.playSongFromList(songs, randomIndex);
                            Routes.routeTo(const Player(), context);
                          },
                          icon: const Icon(Icons.shuffle_rounded, size: 18),
                          label: const Text('Shuffle'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            textStyle: const TextStyle(fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
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
      return _SongListSkeleton(controller: _shimmerController);
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .error
                      .withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.cloud_off_rounded,
                    size: 40, color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
              Text('Couldn\'t load songs',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Check your connection and try again',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
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
        ),
      );
    }

    final songs = _songModels ?? [];
    if (songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_off_rounded,
                size: 48,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.25)),
            const SizedBox(height: 12),
            Text('No songs available',
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    }

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

// ---------------------------------------------------------------------------
// Skeleton shimmer loader that mimics the SongTile layout
// ---------------------------------------------------------------------------

class _SongListSkeleton extends StatelessWidget {
  final AnimationController controller;

  const _SongListSkeleton({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 10,
      itemBuilder: (context, index) {
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return _SkeletonSongTile(
              shimmerValue: controller.value,
              index: index,
            );
          },
        );
      },
    );
  }
}

class _SkeletonSongTile extends StatelessWidget {
  final double shimmerValue;
  final int index;

  const _SkeletonSongTile({
    required this.shimmerValue,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surfaceContainerHighest;
    final highlightColor = theme.colorScheme.surfaceContainerLow;

    // Stagger the shimmer per row for a wave effect
    final offset = (shimmerValue + index * 0.06) % 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            // Accent bar placeholder
            Container(
              width: 3,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            // Track number placeholder
            SizedBox(
              width: 28,
              child: Center(
                child: _ShimmerBox(
                  width: 16,
                  height: 14,
                  borderRadius: 4,
                  offset: offset,
                  baseColor: baseColor,
                  highlightColor: highlightColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Artwork placeholder
            _ShimmerBox(
              width: 48,
              height: 48,
              borderRadius: 10,
              offset: offset,
              baseColor: baseColor,
              highlightColor: highlightColor,
            ),
            const SizedBox(width: 14),
            // Title + Artist text lines
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ShimmerBox(
                    width: 100 + (index % 3) * 40.0,
                    height: 14,
                    borderRadius: 4,
                    offset: offset,
                    baseColor: baseColor,
                    highlightColor: highlightColor,
                  ),
                  const SizedBox(height: 6),
                  _ShimmerBox(
                    width: 70 + (index % 2) * 30.0,
                    height: 12,
                    borderRadius: 4,
                    offset: offset,
                    baseColor: baseColor,
                    highlightColor: highlightColor,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Duration placeholder
            _ShimmerBox(
              width: 32,
              height: 12,
              borderRadius: 4,
              offset: offset,
              baseColor: baseColor,
              highlightColor: highlightColor,
            ),
            const SizedBox(width: 4),
            // Options icon placeholder
            _ShimmerBox(
              width: 18,
              height: 18,
              borderRadius: 9,
              offset: offset,
              baseColor: baseColor,
              highlightColor: highlightColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final double offset;
  final Color baseColor;
  final Color highlightColor;

  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.offset,
    required this.baseColor,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          colors: [baseColor, highlightColor, baseColor],
          stops: const [0.0, 0.5, 1.0],
          begin: Alignment(-1.0 + 2.0 * offset, 0),
          end: Alignment(1.0 + 2.0 * offset, 0),
        ),
      ),
    );
  }
}
