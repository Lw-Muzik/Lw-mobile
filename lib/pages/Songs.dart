import 'package:eq_app/Global/index.dart';
import 'package:eq_app/Helpers/Channel.dart';
import 'package:eq_app/widgets/ArtworkWidget.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../Helpers/index.dart';
import '../controllers/AppController.dart';

class AllSongs extends StatefulWidget {
  const AllSongs({super.key});

  @override
  State<AllSongs> createState() => _AllSongsState();
}

class _AllSongsState extends State<AllSongs> {
  ScrollController scrollController = ScrollController();
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    scrollController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(builder: (context, controller, ch) {
      return FutureBuilder<List<SongModel>>(
        // Default values:
        future: controller.audioQuery.querySongs(
          orderType: OrderType.ASC_OR_SMALLER,
          uriType: UriType.EXTERNAL,
          ignoreCase: true,
        ),

        builder: (context, item) {
          // Waiting content.
          if (item.data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          // 'Library' is empty.
          if (item.data!.isEmpty) {
            return const Text("Nothing found!");
          }
          // controller.au.playerStateStream.listen((event) {
          //   if (event.playing) {
          //     if (scrollController.hasClients) {
          //       // print(scrollController!.offset);
          //       // scrollController.animateTo(
          //       //   controller.songId.toDouble() * 56,
          //       //   duration: const Duration(milliseconds: 900),
          //       //   curve: Curves.decelerate,
          //       // );
          //     }
          //   }
          // });
          // You can use [item.data!] direct or you can create a:
          // List<SongModel> songs = item.data!;
          return Scrollbar(
            controller: scrollController,
            child: ListView.builder(
              controller: scrollController,
              itemCount: item.data!.length,
              itemBuilder: (context, index) {
                return Container(
                  decoration: commonDeration(controller, index, context),
                  child: ListTile(
                    selected: controller.songId == index,
                    // selectedTileColor:

                    selectedColor:
                        Theme.of(context).brightness == Brightness.light
                            ? Theme.of(context).primaryColor
                            : Theme.of(context).primaryColorLight,
                    title: Text(
                      item.data![index].title,
                      maxLines: 1,
                      overflow: item.data![index].title.length > 32
                          ? TextOverflow.fade
                          : TextOverflow.visible,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    subtitle: Text(item.data![index].artist ?? "No Artist"),
                    trailing: SizedBox(
                      width: 90,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Icon(
                            controller.songId == index &&
                                    controller.audioHandler.playing
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_fill,
                            color: Colors.white,
                          ),
                          const Icon(Icons.more_vert, color: Colors.white)
                        ],
                      ),
                    ),

                    onTap: () {
                      controller.songId = index;

                      if (controller.songs.length < item.data!.length) {
                        controller.songs = item.data!;
                      }
                      loadAudioSource(
                          controller.audioHandler, item.data![index]);
                    },
                    leading: ArtworkWidget(
                        path: item.data![index].data,
                        songId: item.data![index].id),
                  ),
                );
              },
            ),
          );
        },
      );
    });
  }
}
