import 'package:eq_app/Global/index.dart';
import 'package:eq_app/Helpers/index.dart';
import 'package:eq_app/Routes/routes.dart';

import 'package:eq_app/extensions/index.dart';
import '/exports/exports.dart';

import '../helpers/audio_handler.dart';
import '../controllers/app_controller.dart';
import '../widgets/bottom_player.dart';
import '../widgets/song_tile.dart';

class PlaylistSongs extends StatefulWidget {
  final int playlistId;
  final String playlist;
  final int songs;
  const PlaylistSongs({
    super.key,
    required this.playlistId,
    required this.playlist,
    required this.songs,
  });

  @override
  State<PlaylistSongs> createState() => _PlaylistSongsState();
}

class _PlaylistSongsState extends State<PlaylistSongs> {
  late Future<List<SongModel>> _songsFuture;

  @override
  void initState() {
    super.initState();
    _songsFuture = OnAudioQuery().queryAudiosFrom(
      AudiosFromType.PLAYLIST,
      widget.playlistId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return NestedScrollView(
      headerSliverBuilder: (context, h) {
        return [
          SliverAppBar(
            forceMaterialTransparency: context.watch<AppController>().isFancy,
            expandedHeight: 400,
            shadowColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: true,
              background: Hero(
                tag: 'playlist_${widget.playlistId}',
                child: Stack(
                  children: [
                    FutureBuilder<List<SongModel>>(
                      future: _songsFuture,
                      builder: (context, snapshot) {
                        return snapshot.hasData
                            ? Consumer<AppController>(
                                builder: (context, controller, child) {
                                  return snapshot.data!.isNotEmpty
                                      ? headerWidget(
                                          controller,
                                          context,
                                          data: snapshot.data!,
                                        )
                                      : Container();
                                },
                              )
                            : Container();
                      },
                    ),
                    Positioned(
                      bottom: 45,
                      left: 10,
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: "${widget.playlist}\n",
                              style: Theme.of(context).textTheme.displayMedium,
                            ),
                            TextSpan(
                              text: "${widget.songs}",
                              style: Theme.of(context).textTheme.headlineLarge!
                                  .copyWith(fontWeight: FontWeight.w300),
                            ),
                            TextSpan(
                              text: widget.songs.aTracks,
                              style: Theme.of(context).textTheme.headlineSmall!
                                  .copyWith(fontWeight: FontWeight.w300),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ];
      },
      body: Consumer<AppController>(
        builder: (context, controller, child) {
          return StreamBuilder(
            stream: context.read<HypeAudioHandler>().player.playingStream,
            builder: (context, service) {
              return Scaffold(
                backgroundColor: controller.isFancy
                    ? Colors.transparent
                    : Theme.of(context).scaffoldBackgroundColor,
                body: FutureBuilder<List<SongModel>>(
                  future: _songsFuture,
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(
                        child: CircularProgressIndicator.adaptive(),
                      );
                    }
                    return SongListView(
                      songs: snap.data ?? [],
                      controller: controller,
                      onTap: (song, index) {
                        controller.playSongFromList(snap.data!, index);
                      },
                      onLongPress: (song, index) {
                        showModalBottomSheet(
                          context: context,
                          builder: (context) => BottomSheet(
                            onClosing: () {},
                            builder: (context) => PlayListEditor(
                              audioId: song.id,
                              song: song.title,
                              playlist: widget.playlistId,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                bottomNavigationBar: controller.hasNowPlaying
                    ? BottomPlayer(controller: controller)
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}

class PlayListEditor extends StatefulWidget {
  final int audioId;
  final String song;
  final int playlist;
  const PlayListEditor({
    super.key,
    required this.audioId,
    required this.song,
    required this.playlist,
  });

  @override
  State<PlayListEditor> createState() => _PlayListEditorState();
}

class _PlayListEditorState extends State<PlayListEditor> {
  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, c) {
        return SizedBox(
          height: 150,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text("Remove from playlist"),
                onTap: () {
                  controller.audioQuery
                      .removeFromPlaylist(widget.playlist, widget.audioId)
                      .then((value) {
                        if (value) {
                          Routes.pop(context);
                          showMessage(
                            context: context,
                            type: 'success',
                            msg: "${widget.song} removed successfully",
                          );
                        }
                      });
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
