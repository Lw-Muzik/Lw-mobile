import 'package:eq_app/Global/index.dart';
import 'package:eq_app/Routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../controllers/AppController.dart';
import '../player/PlayerUI.dart';
import '../widgets/ArtworkWidget.dart';

class SearchPage extends SearchDelegate<SongModel> {
  @override
  String get searchFieldLabel => "Search Songs";
  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        onPressed: () => query = "",
        icon: const Icon(Icons.close),
      ),
    ];
  }

  // Widget buildFlexibleSpace(context) {
  //   return Row(
  //     children: [Chip(label: Text("All Songs"))],
  //   );
  // }

  @override
  Widget? buildLeading(BuildContext context) {
    return InkWell(
      child: const Icon(Icons.arrow_back_ios_new),
      onTap: () => Routes.pop(context),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return Consumer<AppController>(builder: (context, controller, child) {
      var songs = controller.songs
          .where((element) =>
              element.title.toLowerCase().contains(query.toLowerCase()))
          .toList();
      return ListView.builder(
        itemCount: songs.length,
        itemBuilder: (context, i) => ListTile(
          onTap: () {
            int songIndex = (controller.songs
                .indexWhere((result) => result.title == songs[i].title));
            controller.songId = songIndex;
            loadAudioSource(controller.handler, controller.songs[songIndex]);

            Routes.routeTo(const Player(), context);
          },
          leading: ArtworkWidget(
            songId: songs[i].id,
            type: ArtworkType.AUDIO,
            path: songs[i].data,
          ),
          title: Text(
            songs[i].title,
          ),
          subtitle: Text(
            songs[i].artist ?? "Unknown artist",
          ),
        ),
      );
    });
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return Consumer<AppController>(builder: (context, controller, child) {
      var songs = controller.songs
          .where((element) =>
              element.title.toLowerCase().contains(query.toLowerCase()))
          .toList();
      return ListView.builder(
        itemCount: songs.length,
        itemBuilder: (context, i) => ListTile(
          leading: ArtworkWidget(
            songId: songs[i].id,
            type: ArtworkType.AUDIO,
            path: songs[i].data,
          ),
          title: Text(
            songs[i].title,
          ),
          onTap: () {
            // controller.songId = (controller.songs.indexWhere((result) =>
            //     result.title.toLowerCase() == songs[i].title.toLowerCase()));
            int songIndex = (controller.songs
                .indexWhere((result) => result.title == songs[i].title));
            controller.songId = songIndex;
            loadAudioSource(controller.handler, controller.songs[songIndex]);
            Routes.routeTo(const Player(), context);
          },
          subtitle: Text(
            songs[i].artist ?? "Unknown artist",
          ),
        ),
      );
    });
  }
}
