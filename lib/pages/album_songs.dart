import 'dart:ui';

import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/controllers/AppController.dart';
import 'package:eq_app/extensions/index.dart';
import 'package:eq_app/widgets/Body.dart';
import '/exports/exports.dart';

import '/Global/index.dart';
import '/widgets/ArtworkWidget.dart';
import '/widgets/BottomPlayer.dart';
import '/widgets/song_options_sheet.dart';
import '/widgets/song_tile.dart';

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
                  body: FutureBuilder<List<SongModel>>(
                    future: OnAudioQuery.platform.queryAudiosFrom(
                      AudiosFromType.ALBUM_ID,
                      widget.albumId!,
                    ),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator.adaptive(),
                        );
                      }
                      return SongListView(
                        songs: snapshot.data ?? [],
                        controller: controller,
                        onTap: (song, index) {
                          controller.playSongFromList(snapshot.data!, index);
                        },
                        onLongPress: (song, index) {
                          showModalBottomSheet(
                            context: context,
                            builder: (_) => SongOptionsSheet(song: song),
                          );
                        },
                      );
                    },
                  ),
                  bottomNavigationBar: service.data ?? false
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

