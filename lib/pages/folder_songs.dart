import 'package:eq_app/Global/index.dart';
import 'package:eq_app/Helpers/Files.dart';
import '/exports/exports.dart';
import '../controllers/AppController.dart';
import '../player/player_ui.dart';
import '../widgets/BottomPlayer.dart';
import '/widgets/PlayListWidget.dart';
import '/widgets/song_tile.dart';
import '/Routes/routes.dart';

class FolderSongs extends StatefulWidget {
  final String path;
  const FolderSongs({super.key, required this.path});

  @override
  State<FolderSongs> createState() => _FolderSongsState();
}

class _FolderSongsState extends State<FolderSongs> {
  late Future<List<SongModel>> _songsFuture;
  int _songCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeSongs();
  }

  void _initializeSongs() {
    _songsFuture = Files.queryFromFolder(widget.path);
    _songsFuture.then((songs) {
      if (mounted) {
        setState(() => _songCount = songs.length);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, appController, _) => NestedScrollView(
        headerSliverBuilder: (context, _) => [
          _buildSliverAppBar(context, appController),
        ],
        body: _buildBody(appController),
      ),
    );
  }

  SliverAppBar _buildSliverAppBar(
    BuildContext context,
    AppController appController,
  ) {
    return SliverAppBar(
      forceMaterialTransparency: appController.isFancy,
      expandedHeight: 400,
      shadowColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        background: _buildFlexibleSpaceBackground(context),
      ),
    );
  }

  Widget _buildFlexibleSpaceBackground(BuildContext context) {
    return Hero(
      tag: 'folder_${widget.path}',
      child: Stack(
        children: [
          FutureBuilder<List<SongModel>>(
            future: _songsFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();

              return Consumer<AppController>(
                builder: (context, controller, _) =>
                    headerWidget(controller, context, data: snapshot.data!),
              );
            },
          ),
          Positioned(bottom: 45, left: 10, child: _buildFolderInfo(context)),
        ],
      ),
    );
  }

  Widget _buildFolderInfo(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final folderName = widget.path.split("/").last;

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: "$folderName\n", style: textTheme.displayMedium),
          TextSpan(
            text: "$_songCount",
            style: textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.w300,
            ),
          ),
          TextSpan(
            text: _songCount == 1
                ? " Available Track\n"
                : " Available Tracks\n",
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w300,
            ),
          ),
          TextSpan(
            text: widget.path,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
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
          body: _buildSongList(),
          bottomNavigationBar: isPlaying
              ? BottomPlayer(controller: controller)
              : null,
        );
      },
    );
  }

  Widget _buildSongList() {
    return FutureBuilder<List<SongModel>>(
      future: _songsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        return Consumer<AppController>(
          builder: (context, controller, _) {
            return SongListView(
              songs: snapshot.data!,
              controller: controller,
              onTap: (song, index) {
                controller.playSongFromList(snapshot.data!, index);
                Routes.routeTo(const Player(), context);
              },
              onLongPress: (song, index) {
                showModalBottomSheet(
                  context: context,
                  builder: (context) => BottomSheet(
                    onClosing: () {},
                    builder: (context) =>
                        PlaylistWidget(audioId: song.id, song: song.title),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
