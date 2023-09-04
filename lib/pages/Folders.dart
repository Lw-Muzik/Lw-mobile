import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/pages/FolderSongs.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

class Folders extends StatefulWidget {
  const Folders({super.key});

  @override
  State<Folders> createState() => _FoldersState();
}

class _FoldersState extends State<Folders> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
        stream: Stream.fromFuture(OnAudioQuery.platform.queryAllPath()),
        builder: (context, snapshot) {
          return GridView.count(
            crossAxisCount: 3,
            crossAxisSpacing: 26,
            mainAxisSpacing: 26,
            children: List.generate(
              snapshot.data?.length ?? 0,
              (index) => InkWell(
                onTap: () {
                  Routes.routeTo(
                      FolderSongs(path: snapshot.data![index]), context);
                },
                child: GridTile(
                  footer: Text(
                    snapshot.data?[index].split("/").last ?? "",
                    textAlign: TextAlign.center,
                  ),
                  child: const Icon(
                    Icons.folder,
                    size: 60,
                  ),
                ),
              ),
            ),
          );
        });
  }
}
