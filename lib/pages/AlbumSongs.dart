// ignore_for_file: prefer_is_empty

import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/controllers/AppController.dart';
import 'package:eq_app/extensions/index.dart';
import 'package:eq_app/widgets/Body.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../Global/index.dart';
import '../widgets/ArtworkWidget.dart';
import '../widgets/BottomPlayer.dart';

class AlbumSongs extends StatefulWidget {
  final int? albumId;
  final String album;
  final int songs;
  const AlbumSongs(
      {super.key,
      required this.albumId,
      required this.album,
      required this.songs});

  @override
  State<AlbumSongs> createState() => _AlbumSongsState();
}

class _AlbumSongsState extends State<AlbumSongs> {
  @override
  Widget build(BuildContext context) {
    return Body(
      child: NestedScrollView(
        floatHeaderSlivers: true,
        headerSliverBuilder: (context, x) {
          return [
            SliverAppBar(
              toolbarHeight: 300,
              leading: IconButton.filledTonal(
                  onPressed: () => Routes.pop(context),
                  icon: const Icon(Icons.arrow_back)),
              // floating: true,
              // snap: true,
              flexibleSpace: FlexibleSpaceBar(
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
                        songId: widget.albumId!,
                        other: widget.album,
                        type: ArtworkType.ALBUM,
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
              ),
            )
          ];
        },
        body: Consumer<AppController>(builder: (context, controller, child) {
          return StreamBuilder(
              stream: controller.audioHandler.playingStream,
              builder: (context, service) {
                return Scaffold(
                  // backgroundColor: Colors.transparent,
                  body: FutureBuilder(
                    future: controller.audioQuery.queryAudiosFrom(
                      AudiosFromType.ALBUM_ID,
                      widget.albumId!,
                    ),
                    builder: (context, snapshot) {
                      return snapshot.hasData
                          ? SongLists(songs: snapshot.data ?? [])
                          : const Center(
                              child: CircularProgressIndicator.adaptive(),
                            );
                    },
                  ),
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

class SongLists extends StatefulWidget {
  final List<SongModel> songs;
  const SongLists({super.key, required this.songs});

  @override
  State<SongLists> createState() => _SongListsState();
}

class _SongListsState extends State<SongLists> {
  int _selected = -1;
  @override
  Widget build(BuildContext context) {
    return widget.songs.length < 0
        ? Center(
            child: Text(
              "No songs found",
              style: Theme.of(context).textTheme.titleMedium,
            ),
          )
        : ListView.builder(
            itemCount: widget.songs.length,
            itemBuilder: (context, index) {
              return Consumer<AppController>(
                  builder: (context, controller, ch) {
                return Container(
                  margin: const EdgeInsets.only(left: 10, right: 10),
                  decoration: commonDeration(controller, _selected, context),
                  child: ListTile(
                    selected: controller.songId == _selected,
                    selectedTileColor:
                        Theme.of(context).primaryColorLight.withOpacity(0.3),
                    selectedColor: Theme.of(context).primaryColorLight,
                    title: Text(widget.songs[index].title),
                    subtitle: Text(widget.songs[index].artist ?? "No Artist"),
                    trailing: const Icon(Icons.arrow_forward_rounded),
                    onTap: () {
                      setState(() {
                        _selected = index;
                      });
                      if (widget.songs.length > controller.songs.length) {
                        controller.songs = widget.songs;
                      }
                      int songIndex = controller.songs.indexWhere((result) =>
                          result.title == widget.songs[index].title);
                      controller.songId = songIndex;

                      loadAudioSource(
                          controller.audioHandler, controller.songs[songIndex]);
                      // controller.audioPlayer.setUrl(controller
                      //     .songs[]
                      //     .data);
                      // controller.audioPlayer.play();
                      // controller.songs = songs;
                      // controller.songId = index;

                      // controller.audioPlayer.setUrl(songs[index].data);
                      // controller.audioPlayer.play();
                      // Channel.setSessionId(
                      //     controller.audioPlayer.androidAudioSessionId ?? 0);
                    },
                    // This Widget will query/load image.
                    // You can use/create your own widget/method using [queryArtwork].
                    leading: ArtworkWidget(
                      height: 60,
                      width: 60,
                      path: widget.songs[index].data,
                      songId: widget.songs[index].id,
                      type: ArtworkType.AUDIO,
                    ),
                  ),
                );
              });
            });
  }
}
