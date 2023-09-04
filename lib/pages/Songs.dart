import 'package:eq_app/Helpers/Channel.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../controllers/AppController.dart';

class AllSongs extends StatefulWidget {
  const AllSongs({super.key});

  @override
  State<AllSongs> createState() => _AllSongsState();
}

class _AllSongsState extends State<AllSongs> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Consumer<AppController>(builder: (context, controller, child) {
        return FutureBuilder<List<SongModel>>(
          // Default values:
          future: controller.audioQuery.querySongs(
            sortType: null,
            orderType: OrderType.ASC_OR_SMALLER,
            uriType: UriType.EXTERNAL,
            ignoreCase: true,
          ),

          builder: (context, item) {
            // Display error, if any.
            if (item.hasError) {
              return Text(item.error.toString());
            }

            // Waiting content.
            if (item.data == null) {
              return const CircularProgressIndicator();
            }

            // 'Library' is empty.
            if (item.data!.isEmpty) {
              return const Text("Nothing found!");
            }

            // You can use [item.data!] direct or you can create a:
            // List<SongModel> songs = item.data!;
            return ListView.builder(
              itemCount: item.data!.length,
              itemBuilder: (context, index) {
                return ListTile(
                  selected: controller.songId == index,
                  selectedTileColor:
                      Theme.of(context).primaryColorDark.withOpacity(0.1),
                  selectedColor: Theme.of(context).primaryColor,
                  title: Text(item.data![index].title),
                  subtitle: Text(item.data![index].artist ?? "No Artist"),
                  trailing: const Icon(Icons.arrow_forward_rounded),
                  onTap: () {
                    setState(() {
                      controller.songId = index;
                    });
                    controller.audioPlayer.setUrl(item.data![index].data);
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
                    id: item.data![index].id,
                    type: ArtworkType.AUDIO,
                  ),
                );
              },
            );
          },
        );
      }),
    );
  }
}
