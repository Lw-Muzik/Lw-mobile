// ignore_for_file: prefer_is_empty

import 'dart:ui';

import 'package:eq_app/Global/index.dart';
import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/controllers/AppController.dart';
import 'package:eq_app/widgets/Body.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../Helpers/Channel.dart';
import '../widgets/BottomPlayer.dart';

class ArtistSongs extends StatefulWidget {
  final int? artistId;
  final String artist;
  const ArtistSongs({super.key, required this.artistId, required this.artist});

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
              toolbarHeight: 300,
              leading: IconButton.filledTonal(
                  onPressed: () => Routes.pop(context),
                  icon: Icon(Icons.arrow_back)),
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
                background: QueryArtworkWidget(
                  artworkBorder: BorderRadius.zero,
                  format: ArtworkFormat.PNG,
                  size: 5000,
                  quality: 100,
                  artworkWidth: MediaQuery.of(context).size.width,
                  artworkHeight: MediaQuery.of(context).size.width,
                  nullArtworkWidget: ClipRRect(
                    child: Image.asset(
                      "assets/audio.jpeg",
                      fit: BoxFit.cover,
                    ),
                  ),
                  id: widget.artistId!,
                  type: ArtworkType.ARTIST,
                ),
              ),
            )
          ];
        },
        body: Consumer<AppController>(builder: (context, controller, child) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: FutureBuilder(
              future: controller.audioQuery.queryAudiosFrom(
                AudiosFromType.ARTIST_ID,
                widget.artistId!,
              ),
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
            bottomNavigationBar: controller.audioPlayer.playing
                ? BottomPlayer(
                    controller: controller,
                  )
                : null,
          );
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
                return Container(
                  decoration: commonDeration(controller, index, context),
                  child: ListTile(
                    selected: controller.songId == index,
                    selectedTileColor:
                        Theme.of(context).primaryColor.withOpacity(0.1),
                    selectedColor: Theme.of(context).primaryColor,
                    title: Text(
                      songs[index].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      songs[index].artist ?? "No Artist",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.arrow_forward_rounded),
                    onTap: () {
                      controller.songId = (controller.songs.indexWhere(
                          (result) => result.title == songs[index].title));

                      controller.audioPlayer.setUrl(controller
                          .songs[controller.songs.indexWhere(
                              (result) => result.title == songs[index].title)]
                          .data);
                      controller.audioPlayer.play();
                      // controller.songs = songs;
                      // controller.songId = index;

                      // controller.audioPlayer.setUrl(songs[index].data);
                      // controller.audioPlayer.play();
                      // Channel.setSessionId(
                      //     controller.audioPlayer.androidAudioSessionId ?? 0);
                    },
                    // This Widget will query/load image.
                    // You can use/create your own widget/method using [queryArtwork].
                    leading: QueryArtworkWidget(
                      artworkHeight: 60,
                      artworkWidth: 60,
                      nullArtworkWidget: ClipRRect(
                        borderRadius: BorderRadius.circular(60),
                        child: Image.asset("assets/audio.jpeg"),
                      ),
                      controller: controller.audioQuery,
                      id: songs[index].id,
                      type: ArtworkType.AUDIO,
                    ),
                  ),
                );
              });
            });
  }
}
