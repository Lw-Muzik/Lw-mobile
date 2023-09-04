import 'package:flutter/material.dart';

import '../../controllers/AppController.dart';

class MusicInfo extends StatelessWidget {
  final AppController controller;
  const MusicInfo({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return // Music info
        Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 15),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  controller.songs[controller.songId].title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall!.apply(
                        color: Colors.white,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  controller.songs[controller.songId].artist ??
                      "Unknown artist",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge!
                      .apply(color: Colors.white.withOpacity(0.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
