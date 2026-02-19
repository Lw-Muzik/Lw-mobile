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
        }
      }
      if (mounted) {
        setState(() {
          _songModels = models;
          _loading = false;
        });
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
