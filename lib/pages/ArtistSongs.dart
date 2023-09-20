// ignore_for_file: prefer_is_empty

import 'dart:ui';

import 'package:eq_app/Global/index.dart';
import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/controllers/AppController.dart';
import 'package:eq_app/extensions/index.dart';
import 'package:eq_app/widgets/Body.dart';
import 'package:eq_app/widgets/PlayListWidget.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../player/PlayerUI.dart';
import '../widgets/ArtworkWidget.dart';
import '../widgets/BottomPlayer.dart';

class ArtistSongs extends StatefulWidget {
  final int? artistId;
  final int songs;
  final int albums;
  final String artist;
  const ArtistSongs(
      {super.key,
      required this.artistId,
      required this.artist,
      required this.songs,
      required this.albums});

  @override
  State<ArtistSongs> createState() => _ArtistSongsState();
}

class _ArtistSongsState extends State<ArtistSongs> {
  @override
  Widget build(BuildContext context) {
    return Body(
      child: NestedScrollView(
        floatHeaderSlivers: true,
        headerSliverBuilder: (context, x) {
          return [
            SliverAppBar(
              expandedHeight: 400,
              leading: IconButton.filledTonal(
                  onPressed: () => Routes.pop(context),
                  icon: const Icon(Icons.arrow_back)),
              // floating: true,
              // snap: true,
              flexibleSpace: FlexibleSpaceBar(
                centerTitle: true,
                title: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: Text(
                      widget.artist,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                expandedTitleScale: 70,
                background: Stack(
                  children: [
                    headerWidget(
                      context.read<AppController>(),
                      context,
                      child: ArtworkWidget(
                        borderRadius: BorderRadius.zero,
                        size: 5000,
                        quality: 100,
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.width,
                        songId: widget.artistId!,
                        other: widget.artist,
                        type: ArtworkType.ARTIST,
                      ),
                    ),
                    Positioned(
                      bottom: 45,
                      left: 20,
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: "${widget.artist}\n",
                              style: Theme.of(context).textTheme.titleLarge,
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
                            // TextSpan(
                            //   text: widget.albums.nAlbums,
                            //   style: Theme.of(context)
                            //       .textTheme
                            //       .titleLarge!
                            //       .copyWith(fontWeight: FontWeight.w600),
                            // ),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),
            )
          ];
        },
        body: Consumer<AppController>(builder: (context, controller, child) {
          return StreamBuilder(
              stream: controller.audioHandler.playingStream,
              builder: (context, service) {
                return Scaffold(
                  body: FutureBuilder(
                    future: controller.audioQuery.queryAudiosFrom(
                        AudiosFromType.ARTIST_ID, widget.artistId ?? 0,
                        ignoreCase: true),
                    builder: (context, snapshot) {
                      return snapshot.hasData
                          ? SongLists(songs: snapshot.data ?? [])
                          : const Center(
                              child: CircularProgressIndicator.adaptive(),
                            );
                    },
                  ),
                  floatingActionButtonLocation:
                      FloatingActionButtonLocation.centerDocked,
                  bottomNavigationBar: service.data ?? false
                      ? BottomPlayer(
                          controller: controller,
                        )
                      : null,
                );
              });
        }),
      ),
    );
  }
}

class SongLists extends StatelessWidget {
  final List<SongModel> songs;
  const SongLists({super.key, required this.songs});

  @override
  Widget build(BuildContext context) {
    return songs.length < 0
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
                return Routes.animateTo(
                  closedWidget: Container(
                    margin: const EdgeInsets.only(left: 10, right: 10),
                    decoration: commonDeration(controller, index, context),
                    child: ListTile(
                      selected: controller.songId == index,
                      onLongPress: () {
                        // showModalBottomSheet(context: context, builder: builder)
                        showModalBottomSheet(
                            context: context,
                            builder: (context) {
                              return BottomSheet(
                                  onClosing: () {},
                                  builder: (context) {
                                    return PlaylistWidget(
                                      audioId: controller.songs[index].id,
                                      song: controller.songs[index].title,
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
                      trailing: const Icon(Icons.arrow_forward_rounded),
                      onTap: () {
                        if (controller.songs.length != songs.length) {
                          controller.songs = songs;
                        }
                        int songIndex = controller.songs.indexWhere(
                            (result) => result.title == songs[index].title);
                        controller.songId = songIndex;
                        loadAudioSource(controller.audioHandler,
                            controller.songs[songIndex]);
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
                  ),
                  openWidget: const Player(),
                );
              });
            });
  }
}
