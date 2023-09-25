// ignore_for_file: non_constant_identifier_names

import 'package:eq_app/Global/index.dart';
import 'package:eq_app/Helpers/index.dart';
import 'package:eq_app/Routes/routes.dart';

import 'package:eq_app/extensions/index.dart';
import 'package:eq_app/pages/ArtistSongs.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../Helpers/AudioHandler.dart';
import '../controllers/AppController.dart';
import '../widgets/ArtworkWidget.dart';
import '../widgets/BottomPlayer.dart';

class PlaylistSongs extends StatefulWidget {
  final int playlist_id;
  final String playlist;
  final int songs;
  const PlaylistSongs(
      {super.key,
      required this.playlist_id,
      required this.playlist,
      required this.songs});

  @override
  State<PlaylistSongs> createState() => _PlaylistSongsState();
}

class _PlaylistSongsState extends State<PlaylistSongs> {
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
              background: Stack(
                children: [
                  StreamBuilder<List<SongModel>>(
                      stream: Stream.fromFuture(OnAudioQuery().queryAudiosFrom(
                          AudiosFromType.PLAYLIST, widget.playlist_id)),
                      builder: (context, snapshot) {
                        return snapshot.hasData
                            ? Consumer<AppController>(
                                builder: (context, controller, child) {
                                return snapshot.data!.isNotEmpty
                                    ? headerWidget(controller, context,
                                        data: snapshot.data!)
                                    : Container();
                              })
                            : Container();
                      }),
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
                            style: Theme.of(context)
                                .textTheme
                                .headlineLarge!
                                .copyWith(fontWeight: FontWeight.w300),
                          ),
                          TextSpan(
                            text: widget.songs.aTracks,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall!
                                .copyWith(fontWeight: FontWeight.w300),
                          ),
                        ],
                      ),
                    ),
                  )
                ],
              ),
              // title: ,
            ),
          )
        ];
      },
      body: Consumer<AppController>(builder: (context, controller, child) {
        return StreamBuilder(
            stream: context.read<AudioHandler>().player.playingStream,
            builder: (context, service) {
              return Scaffold(
                backgroundColor: controller.isFancy
                    ? Colors.transparent
                    : Theme.of(context).scaffoldBackgroundColor,
                body: Stack(
                  children: [
                    FutureBuilder(
                      future: (OnAudioQuery().queryAudiosFrom(
                          AudiosFromType.PLAYLIST, widget.playlist_id)),
                      builder: (context, snap) {
                        return snap.hasData
                            ? PlaylistSongLists(
                                songs: snap.data ?? [],
                                playlist: widget.playlist_id,
                              )
                            : const Center(
                                child: CircularProgressIndicator.adaptive());
                      },
                    ),
                  ],
                ),
                bottomNavigationBar: service.data ?? false
                    ? BottomPlayer(
                        controller: controller,
                      )
                    : null,
              );
            });
      }),
    );
  }
}

class PlaylistSongLists extends StatelessWidget {
  final List<SongModel> songs;
  final int playlist;
  const PlaylistSongLists(
      {super.key, required this.songs, required this.playlist});

  @override
  Widget build(BuildContext context) {
    return songs.isEmpty
        ? Center(
            child: Text(
              "No songs found",
              style: Theme.of(context).textTheme.titleMedium,
            ),
          )
        : ListView.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              return Consumer<AppController>(
                  builder: (context, controller, ch) {
                return Container(
                  margin: const EdgeInsets.only(left: 10, right: 10),
                  decoration: commonDeration(controller, index, context),
                  child: ListTile(
                    selected: controller.songId == index,
                    onLongPress: () {
                      showModalBottomSheet(
                          context: context,
                          builder: (context) {
                            return BottomSheet(
                                onClosing: () {},
                                builder: (context) {
                                  return PlayListEditor(
                                    audioId: controller.songs[index].id,
                                    song: controller.songs[index].title,
                                    playlist: playlist,
                                  );
                                });
                          });
                    },
                    selectedTileColor:
                        Theme.of(context).primaryColor.withOpacity(0.1),
                    selectedColor: Theme.of(context).primaryColorLight,
                    title: Text(
                      songs[index].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium!,
                    ),
                    subtitle: Text(
                      songs[index].artist ?? "No Artist",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      "${formatTime(
                        Duration(milliseconds: songs[index].duration ?? 0),
                      )} | ${songs[index].fileExtension}",
                    ),
                    onTap: () {
                      if (controller.songs.length != songs.length) {
                        controller.songs = songs;
                      }
                      int songIndex = (controller.songs.indexWhere(
                          (result) => result.title == songs[index].title));
                      controller.songId = songIndex;
                      loadAudioSource(
                          controller.handler, controller.songs[songIndex]);
                    },
                    // This Widget will query/load image.
                    // You can use/create your own widget/method using [queryArtwork].
                    leading: ArtworkWidget(
                      height: 60,
                      width: 60,
                      songId: songs[index].id,
                      path: songs[index].data,
                      type: ArtworkType.AUDIO,
                    ),
                  ),
                );
              });
            });
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
    return Consumer<AppController>(builder: (context, controller, c) {
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
                        msg: "${widget.song} removed successfully");
                  }
                });
              },
            )
          ],
        ),
      );
    });
  }
}
