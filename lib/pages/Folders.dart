import 'package:eq_app/Helpers/index.dart';
import 'package:eq_app/Routes/routes.dart';

import 'package:eq_app/pages/FolderSongs.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../Global/index.dart';
import '../player/widgets/DeleteWindow.dart';

class Folders extends StatefulWidget {
  const Folders({super.key});

  @override
  State<Folders> createState() => _FoldersState();
}

class _FoldersState extends State<Folders> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
        future: OnAudioQuery.platform.queryAllPath(),
        builder: (context, snapshot) {
          return GridView.count(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
            children: List.generate(
              snapshot.data?.length ?? 0,
              (index) => Container(
                margin: const EdgeInsets.all(10),
                child: InkWell(
                  onLongPress: () {
                    showDeleteWindow("folder", snapshot.data![index], context);
                  },
                  child: Routes.animateTo(
                    closedWidget: GridTile(
                      child: folderArtwork(snapshot.data![index],
                          snapshot.data?[index].split("/").last ?? ""),
                    ),
                    openWidget: FolderSongs(path: snapshot.data?[index] ?? ""),
                  ),
                ),
              ),
            ),
          );
        });
  }
}
