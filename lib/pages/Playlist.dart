import 'package:eq_app/Helpers/index.dart';
import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/controllers/AppController.dart';
import 'package:eq_app/extensions/index.dart';
import 'package:eq_app/pages/PlaylistSongs.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

class PlayListView extends StatefulWidget {
  const PlayListView({super.key});

  @override
  State<PlayListView> createState() => _PlayListViewState();
}

class _PlayListViewState extends State<PlayListView> {
  List<PlaylistModel> _playlist = [];
  TextEditingController textController = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Consumer<AppController>(builder: (context, controller, p) {
          if (mounted) {
            OnAudioQuery.platform.queryPlaylists().asStream().listen((event) {
              if (mounted) {
                setState(() {
                  _playlist = event;
                });
              }
            });
          }
          return FutureBuilder(
              future: controller.audioQuery.queryPlaylists(),
              builder: (context, sna) {
                return sna.hasData
                    ? ListView.builder(
                        itemBuilder: (context, index) {
                          return ListTile(
                            leading: const Icon(
                              Icons.playlist_play,
                              size: 40,
                            ),
                            onLongPress: () => showDeletePlaylist(
                                controller,
                                sna.data![index].playlist,
                                sna.data![index].id,
                                context),
                            onTap: () {
                              Routes.routeTo(
                                PlaylistSongs(
                                    playlist_id: sna.data![index].id,
                                    playlist: sna.data![index].playlist,
                                    songs: sna.data![index].numOfSongs),
                                context,
                              );
                            },
                            title: Text(sna.data![index].playlist),
                            subtitle: Text(sna.data![index].numOfSongs.nSongs),
                          );
                        },
                        itemCount: sna.data!.length,
                      )
                    : const Center(
                        child: Text("No playlists"),
                      );
              });
        }),
        Positioned(
          bottom: 50,
          right: 40,
          child: FloatingActionButton(
            onPressed: () => showAddPlaylist(
                textController, context.read<AppController>(), context),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}
