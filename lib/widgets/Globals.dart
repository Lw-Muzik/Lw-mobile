import 'dart:ui';

import 'package:flutter/material.dart';

import '../controllers/AppController.dart';
import 'ArtworkWidget.dart';

Widget bottomPlayer(AppController controller, BuildContext context) {
  return BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40 * 2),
    child: ListTile(
      leading: Transform.rotate(
          angle: 0,
          child: ArtworkWidget(
            songId: controller.songs[controller.songId].id,
            path: controller.songs[controller.songId].data,
            borderRadius: BorderRadius.circular(60),
          )),
      title: Text(
        controller.songs[controller.songId].title,
        overflow: TextOverflow.ellipsis,
        style:
            Theme.of(context).textTheme.bodyLarge!.apply(color: Colors.white),
      ),
      subtitle: Text(
        controller.songs[controller.songId].artist ?? "Unknown artist",
        overflow: TextOverflow.ellipsis,
        style:
            Theme.of(context).textTheme.bodyLarge!.apply(color: Colors.white),
      ),
      trailing: SizedBox(
        width: 150,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: controller.prev,
              color: Colors.white,
              icon: const Icon(Icons.skip_previous),
            ),
            StreamBuilder(
                stream: controller.audioHandler.playingStream,
                builder: (context, snapshot) {
                  bool? p = snapshot.data;

                  return IconButton(
                    color: Colors.white,
                    onPressed: () {
                      p == true
                          ? controller.audioHandler.pause()
                          : controller.audioHandler.play();
                    },
                    icon: Icon(p == true ? Icons.pause : Icons.play_arrow),
                  );
                }),
            IconButton(
                color: Colors.white,
                onPressed: controller.next,
                icon: const Icon(Icons.skip_next))
          ],
        ),
      ),
    ),
  );
}
