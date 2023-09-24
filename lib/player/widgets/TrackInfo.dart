import 'dart:ui';

import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/pages/ArtistSongs.dart';
import 'package:eq_app/widgets/ArtworkWidget.dart';
import 'package:flutter/material.dart';

import '../../controllers/AppController.dart';
import '../../pages/AlbumSongs.dart';
import '../../widgets/PlayListWidget.dart';

class TrackInfo extends StatelessWidget {
  final AppController controller;
  const TrackInfo({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: InkWell(
        onTap: () {
          Routes.pop(context);
        },
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Center(
            child: SizedBox(
              height: MediaQuery.of(context).size.width,
              child: Card(
                clipBehavior: Clip.hardEdge,
                color: Colors.transparent,
                elevation: 0,
                // color: Colors.grey.shade400!.withOpacity(0.15),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(18.0),
                            child: ArtworkWidget(
                              width: 100,
                              height: 100,
                              songId: controller.songId,
                              path: controller.songs[controller.songId].data,
                            ),
                          ),
                          SizedBox(
                            width: MediaQuery.of(context).size.width / 2,
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text:
                                        "${controller.songs[controller.songId].title}\n",
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                  TextSpan(
                                    text: controller
                                            .songs[controller.songId].artist ??
                                        "Unknown Artist" + " | \n",
                                  ),
                                  TextSpan(
                                    text: " \t|\t ",
                                    style:
                                        Theme.of(context).textTheme.labelLarge,
                                  ),
                                  TextSpan(
                                    text: controller
                                            .songs[controller.songId].album ??
                                        "Unknown",
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.apply(
                                            color: Theme.of(context)
                                                .textTheme
                                                .labelLarge
                                                ?.color!
                                                .withOpacity(0.6)),
                                  )
                                ],
                              ),
                              textWidthBasis: TextWidthBasis.longestLine,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        ],
                      ),
                      ListTile(
                        leading: const Icon(Icons.playlist_add),
                        title: Text(
                          "Add to Playlist",
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        onTap: () {
                          Routes.pop(context);
                          showModalBottomSheet(
                              context: context,
                              builder: (context) {
                                return BottomSheet(
                                  backgroundColor: Colors.transparent,
                                  builder: (context) => PlaylistWidget(
                                    audioId:
                                        controller.songs[controller.songId].id,
                                    song: controller
                                        .songs[controller.songId].title,
                                  ),
                                  onClosing: () {},
                                );
                              });
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.person),
                        onTap: () {
                          Routes.pop(context);
                          Routes.routeTo(
                              ArtistSongs(
                                  artistId: controller
                                      .songs[controller.songId].artistId,
                                  artist: controller
                                          .songs[controller.songId].artist ??
                                      "Unknown Artist",
                                  songs: 0,
                                  albums: 0),
                              context);
                        },
                        title: Text(
                          "Go to Artist",
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.album),
                        title: const Text("Go to Album"),
                        onTap: () {
                          Routes.pop(context);
                          Routes.routeTo(
                              AlbumSongs(
                                albumId:
                                    controller.songs[controller.songId].albumId,
                                album:
                                    controller.songs[controller.songId].album ??
                                        "Unknown Album",
                                songs: 0,
                              ),
                              context);
                        },
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
