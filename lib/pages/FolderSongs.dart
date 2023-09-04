import 'dart:math';

import 'package:eq_app/Helpers/Files.dart';
import 'package:eq_app/pages/ArtistSongs.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../controllers/AppController.dart';

class FolderSongs extends StatefulWidget {
  final String path;
  const FolderSongs({super.key, required this.path});

  @override
  State<FolderSongs> createState() => _FolderSongsState();
}

class _FolderSongsState extends State<FolderSongs> {
  @override
  Widget build(BuildContext context) {
    var songs = Files.queryFromFolder(widget.path);
    return NestedScrollView(
      headerSliverBuilder: (context, h) {
        return [
          SliverAppBar(
              toolbarHeight: 100,
              floating: true,
              snap: true,
              flexibleSpace: FlexibleSpaceBar(
                centerTitle: true,
                title: Center(
                  child: Text(widget.path.split("/").last,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
              ))
        ];
      },
      body: Consumer<AppController>(builder: (context, controller, child) {
        return Scaffold(
          body: ListView.builder(
            itemCount: songs.length,
            itemBuilder: (context, i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 18.0),
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(50),
                    child: Image.asset("assets/audio.jpeg"),
                  ),
                  title: Text("${songs[i]['title']}"),
                  onTap: () {
                    // controller.songs = songs;
                  },
                ),
              );
            },
          ),
          // body:
          // StreamBuilder(
          //   stream: Stream.fromFuture(
          //       OnAudioQuery.platform.queryFromFolder(widget.path)),
          //   builder: (context, snap) {
          //     return snap.hasData
          //         ? SongLists(songs: snap.data ?? [])
          //         : Center(child: const CircularProgressIndicator.adaptive());
          //   },
          // ),
        );
      }),
    );
  }
}
