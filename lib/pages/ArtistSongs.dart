import 'dart:ui';

import 'package:eq_app/controllers/AppController.dart';
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
    return Stack(
      children: [
        QueryArtworkWidget(
          artworkBorder: BorderRadius.zero,
          format: ArtworkFormat.PNG,
          size: 5000,
          quality: 100,
          artworkWidth: MediaQuery.of(context).size.width,
          artworkHeight: MediaQuery.of(context).size.height,
          id: widget.artistId!,
          type: ArtworkType.ARTIST,
        ),
        NestedScrollView(
          headerSliverBuilder: (context, x) {
            return [
              SliverAppBar(
                toolbarHeight: 300,
                floating: true,
                snap: true,
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
              body: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 200, sigmaY: 200),
                child: FutureBuilder(
                  future: controller.audioQuery.queryAudiosFrom(
                      AudiosFromType.ARTIST_ID, widget.artistId!),
                  builder: (context, snapshot) {
                    return snapshot.hasData
                        ? SongLists(songs: snapshot.data ?? [])
                        : const Center(
                            child: CircularProgressIndicator.adaptive(),
                          );
                  },
                ),
              ),
              floatingActionButtonLocation:
                  FloatingActionButtonLocation.centerDocked,
              bottomNavigationBar: controller.audioPlayer.playing
                  ? Container(
                      margin: const EdgeInsets.only(
                          left: 10, bottom: 40, right: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        color: Colors.white70,
                      ),
                      child: BottomPlayer(
                        controller: controller,
                      ),
                    )
                  : null,
            );
          }),
        ),
      ],
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
                  builder: (context, controller, child) {
                return ListTile(
                  selected: controller.songId == index,
                  selectedTileColor:
                      Theme.of(context).primaryColor.withOpacity(0.1),
                  selectedColor: Theme.of(context).primaryColor,
                  title: Text(songs[index].title),
                  subtitle: Text(songs[index].artist ?? "No Artist"),
                  trailing: const Icon(Icons.arrow_forward_rounded),
                  onTap: () {
                    controller.songs = songs;
                    controller.songId = index;

                    controller.audioPlayer.setUrl(songs[index].data);
                    controller.audioPlayer.play();
                    Channel.setSessionId(
                        controller.audioPlayer.androidAudioSessionId ?? 0);
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
                );
              });
            });
  }
}
