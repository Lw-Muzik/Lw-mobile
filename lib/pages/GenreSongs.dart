// ignore_for_file: prefer_is_empty

import 'dart:ui';

import 'package:eq_app/Global/index.dart';
import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/controllers/AppController.dart';
import 'package:eq_app/extensions/index.dart';
import 'package:eq_app/widgets/Body.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../Helpers/AudioHandler.dart';
import '../Helpers/index.dart';
import '../widgets/ArtworkWidget.dart';
import '../widgets/BottomPlayer.dart';

class GenreSongs extends StatefulWidget {
  final int? genreId;
  final String genre;
  final int songs;
  const GenreSongs(
      {super.key,
      required this.genreId,
      required this.genre,
      required this.songs});

  @override
  State<GenreSongs> createState() => _GenreSongsState();
}

class _GenreSongsState extends State<GenreSongs> {
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
                        songId: widget.genreId!,
                        other: widget.genre,
                        type: ArtworkType.GENRE,
                      ),
                    ),
                    Positioned(
                      bottom: 45,
                      left: 20,
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: "${widget.genre}\n",
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
              ),
            )
          ];
        },
        body: Consumer<AppController>(builder: (context, controller, child) {
          return StreamBuilder(
              stream: context.read<AudioHandler>().player.playingStream,
              builder: (context, service) {
                return Scaffold(
                  backgroundColor: Theme.of(context)
                      .scaffoldBackgroundColor
                      .withOpacity(0.8),
                  body: FutureBuilder(
                    future: controller.audioQuery.queryAudiosFrom(
                      AudiosFromType.GENRE_ID,
                      widget.genreId!,
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
                  decoration: commonDeration(controller, index, context),
                  child: ListTile(
                    selected: controller.songId == _selected,
                    selectedTileColor:
                        Theme.of(context).primaryColorLight.withOpacity(0.1),
                    selectedColor: Theme.of(context).primaryColorLight,
                    title: Text(widget.songs[index].title),
                    subtitle: Text(widget.songs[index].artist ?? "No Artist"),
                    trailing: Text(
                      "${formatTime(
                        Duration(
                            milliseconds: widget.songs[index].duration ?? 0),
                      )} | ${widget.songs[index].fileExtension}",
                    ),
                    onTap: () {
                      setState(() {
                        _selected = index;
                      });
                      controller.songs = widget.songs;

                      int songIndex = (controller.songs.indexWhere((result) =>
                          result.title == widget.songs[index].title));
                      controller.songId = songIndex;
                      loadAudioSource(
                          controller.handler, controller.songs[songIndex]);
                    },
                    // This Widget will query/load image.
                    // You can use/create your own widget/method using [queryArtwork].
                    leading: ArtworkWidget(
                      songId: widget.songs[index].id,
                      path: widget.songs[index].data,
                      type: ArtworkType.AUDIO,
                    ),
                  ),
                );
              });
            });
  }
}
