import 'package:eq_app/Global/index.dart';
import 'package:eq_app/controllers/AppController.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

class NowPlaying extends StatefulWidget {
  final AppController controller;
  NowPlaying({super.key, required this.controller});

  @override
  State<NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<NowPlaying> {
  ScrollController scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.width,
      child: StreamBuilder(
          stream: widget.controller.audioHandler.playingStream,
          builder: (context, service) {
            if (service.hasData) {
              if (service.data!) {
                if (scrollController.hasClients) {
                  scrollController.position.animateTo(
                      widget.controller.songId.toDouble() * 72,
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.decelerate);
                }
              }
            }
            List<SongModel> songs = widget.controller.songs;
            return ReorderableListView.builder(
              scrollController: scrollController,
              onReorder: (old, n) {
                if (old < n) n--;
                songs.insert(
                  n,
                  songs.removeAt(old),
                );
              },
              itemCount: songs.length,
              itemBuilder: (context, i) {
                return Dismissible(
                  background: Container(
                    color: Colors.redAccent,
                    alignment: Alignment.centerRight,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 8.0),
                      child: Icon(Icons.delete, color: Colors.white),
                    ),
                  ),
                  key: ValueKey(i),
                  onDismissed: (d) {
                    songs.removeAt(i);
                  },
                  child: ListTile(
                    selected: i == widget.controller.songId,
                    selectedColor: Theme.of(context).primaryColorLight,
                    selectedTileColor:
                        Theme.of(context).primaryColorLight.withOpacity(0.2),
                    leading: const Icon(Icons.menu),
                    onTap: () {
                      setState(() {
                        widget.controller.songId = i;
                      });
                      loadAudioSource(widget.controller.audioHandler, songs[i]);
                      // widget.controller.audioPlayer.setUrl(songs[i].data);
                      // widget.controller.audioPlayer.play();
                    },
                    title: Text(
                      widget.controller.songs[i].title,
                      maxLines: 1,
                    ),
                    subtitle: Text(
                      widget.controller.songs[i].artist ?? "Unknown artist",
                      maxLines: 1,
                    ),
                  ),
                );
              },
            );
          }),
    );
  }
}
