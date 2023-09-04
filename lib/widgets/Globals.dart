import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/player/PlayerUI.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../controllers/AppController.dart';

Widget bottomPlayer(AppController controller, BuildContext context) {
  return ListTile(
    onTap: () {
      Routes.routeTo(const Player(), context, animate: true);
    },
    leading: Transform.rotate(
      angle: 0,
      child: QueryArtworkWidget(
          artworkBorder: BorderRadius.circular(5),
          controller: controller.audioQuery,
          id: controller.songs[controller.songId].id,
          type: ArtworkType.AUDIO,
          nullArtworkWidget: ClipRRect(
            borderRadius: BorderRadius.circular(60),
            child: Image.asset("assets/audio.jpeg"),
          )),
    ),
    title: Text(
      controller.songs[controller.songId].title,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyLarge,
    ),
    subtitle: Text(
      controller.songs[controller.songId].artist ?? "Unknown artist",
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyLarge,
    ),
    trailing: IconButton(
      onPressed: () {
        controller.audioPlayer.setUrl(controller.songs[controller.songId].data);
        controller.audioPlayer.play();
      },
      icon: StreamBuilder<bool>(
          stream: controller.audioPlayer.playingStream,
          builder: (context, snapshot) {
            bool? p = snapshot.data;
            if (p != null) {
              // pPlay = p;
            }
            return Icon(p == true ? Icons.pause : Icons.play_arrow);
          }),
    ),
  );
}
