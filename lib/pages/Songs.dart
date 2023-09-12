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

    // scrollController?.addListener(() {
    //   scrollController?.animateTo(
    //       context.read<AppController>().songId.toDouble(),
    //       duration: const Duration(milliseconds: 900),
    //       curve: Curves.decelerate);
    // });
  }

  @override
  void dispose() {
    super.dispose();
    scrollController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var controller = Provider.of<AppController>(context, listen: true);
    return StreamBuilder<List<SongModel>>(
      // Default values:
      stream: Stream.fromFuture(controller.audioQuery.querySongs(
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      )),

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
        controller.audioPlayer.playerStateStream.listen((event) {
          if (event.playing) {
            if (scrollController.hasClients) {
              // print(scrollController!.offset);
              // scrollController.animateTo(
              //   controller.songId.toDouble() * 56,
              //   duration: const Duration(milliseconds: 900),
              //   curve: Curves.decelerate,
              // );
            }
          }
        });
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
                  trailing: Icon(
                    controller.songId == index
                        ? Icons.equalizer
                        : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  onTap: () {
                    setState(() {
                      controller.songId = index;
                    });
                    if (controller.songs.length < item.data!.length) {
                      controller.songs = item.data!;
                    }

                    controller.audioPlayer.setUrl(item.data![index].data);
                    controller.audioPlayer.play();
                    Channel.setSessionId(
                        controller.audioPlayer.androidAudioSessionId ?? 0);
                  },
                  // This Widget will query/load image.
                  // You can use/create your own widget/method using [queryArtwork].
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
  }
}
