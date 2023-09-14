import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/pages/ArtistSongs.dart';
import 'package:eq_app/widgets/ArtworkWidget.dart';
import 'package:flutter/material.dart';

import '../../controllers/AppController.dart';

class TrackInfo extends StatelessWidget {
  final AppController controller;
  const TrackInfo({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 18.0, right: 18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(18.0),
            child: ArtworkWidget(
              width: MediaQuery.of(context).size.width,
              height: 200,
              songId: controller.songId,
              path: controller.songs[controller.songId].data,
            ),
          ),
          Center(
            child: ListTile(
              leading: Text(
                "Title:",
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              title: Text(controller.songs[controller.songId].title),
            ),
          ),
          ListTile(
            leading: Text(
              "Artist:",
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            onTap: () {
              Routes.pop(context);
              Routes.routeTo(
                  ArtistSongs(
                      artistId: controller.songs[controller.songId].artistId,
                      artist: controller.songs[controller.songId].artist ??
                          "Unknown Artist",
                      songs: 0,
                      albums: 0),
                  context);
            },
            title: Text(
              controller.songs[controller.songId].artist ?? "Unknown Artist",
            ),
          ),
          ListTile(
            leading: Text(
              "Album:",
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            title: Text(controller.songs[controller.songId].album ?? "Unknown"),
          ),
          ListTile(
            leading: Text(
              "Genre:",
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            title: Text(controller.songs[controller.songId].genre ?? "Unknown"),
          )
        ],
      ),
    );
  }
}
