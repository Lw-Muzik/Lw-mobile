import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/controllers/app_controller.dart';
import 'package:eq_app/extensions/index.dart';
import 'package:eq_app/widgets/Body.dart';
import '/exports/exports.dart';

import '../global/index.dart';
import '../widgets/artwork_widget.dart';
import '../widgets/bottom_player.dart';
import '/widgets/song_options_sheet.dart';
import '/widgets/song_tile.dart';
import '/data/library_repository.dart';

class AlbumSongs extends StatefulWidget {
  final int? albumId;
  final String album;
  final int songs;
  const AlbumSongs({
    super.key,
    required this.albumId,
    required this.album,
    required this.songs,
  });

  @override
  State<AlbumSongs> createState() => _AlbumSongsState();
}

class _AlbumSongsState extends State<AlbumSongs> {
  final ScrollController _controller = ScrollController();

  // Built once here (not in build()) so the outer playingStream rebuilds no
  // longer re-issue the query every time playback state flips.
  late final Stream<List<SongModel>> _songsStream = context
      .read<LibraryRepository>()
      .watchAlbumSongs(widget.album);

  @override
  Widget build(BuildContext context) {
    return Body(
      child: NestedScrollView(
        controller: _controller,
        floatHeaderSlivers: true,
        headerSliverBuilder: (context, x) {
          return [
            SliverAppBar(
              expandedHeight: 300,
              leading: IconButton.filledTonal(
                onPressed: () => Routes.pop(context),
                icon: const Icon(Icons.arrow_back),
              ),
              floating: true,
              snap: true,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                // centerTitle: true,
                // title: Text("titi ${_controller.position.pixels}"),
                // expandedTitleScale: 70,
                background: Stack(
                  children: [
                    Hero(
                      tag: 'album_${widget.albumId}',
                      child: headerWidget(
                        context.read<AppController>(),
                        context,
                        child: ArtworkWidget(
                          borderRadius: BorderRadius.zero,
                          size: 5000,
                          quality: 100,
                          width: MediaQuery.of(context).size.width,
                          height: MediaQuery.of(context).size.width,
                          songId: widget.albumId!,
                          other: widget.album,
                          type: ArtworkType.ALBUM,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 45,
                      left: 20,
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: "${widget.album}\n",
                              style: Theme.of(context).textTheme.titleLarge,
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
          ];
        },
        body: Consumer<AppController>(
          builder: (context, controller, child) {
            return StreamBuilder(
              stream: controller.handler.player.playingStream,
              builder: (context, service) {
                return Scaffold(
                  body: StreamBuilder<List<SongModel>>(
                    stream: _songsStream,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator.adaptive(),
                        );
                      }
                      final songs = snapshot.data!;
                      return SongListView(
                        songs: songs,
                        controller: controller,
                        onTap: (song, index) {
                          controller.playSongFromList(songs, index);
                        },
                        onLongPress: (song, index) {
                          showModalBottomSheet(
                            context: context,
                            builder: (_) => SongOptionsSheet(song: song),
                          );
                        },
                        onOptions: (song, index) {
                          showModalBottomSheet(
                            context: context,
                            builder: (_) => SongOptionsSheet(song: song),
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
      ),
    );
  }
}
