import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '/Routes/routes.dart';
import '/extensions/index.dart';
import 'package:eq_app/pages/AlbumSongs.dart';
import 'package:flutter/material.dart';

import '../controllers/AppController.dart';
import '../widgets/ArtworkWidget.dart';

class Albums extends StatefulWidget {
  const Albums({super.key});

  @override
  State<Albums> createState() => _AlbumsState();
}

class _AlbumsState extends State<Albums> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AlbumModel>>(
        future: context.read<AppController>().audioQuery.queryAlbums(),
        builder: (context, snapshot) {
          return GridView.count(
            crossAxisCount: 3,
            crossAxisSpacing: 26,
            mainAxisSpacing: 26,
            children: List.generate(
              snapshot.data?.length ?? 0,
              (index) => Routes.animateTo(
                closedWidget: GridTile(
                  footer: Card(
                    color: Theme.of(context).cardColor.withOpacity(0.4),
                    child: SizedBox(
                      height: 46,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "${snapshot.data?[index].getMap['album'] ?? 'Unknown'}",
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          Text(snapshot.data![index].numOfSongs.nSongs,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleSmall),
                        ],
                      ),
                    ),
                  ),
                  child: ArtworkWidget(
                    borderRadius: BorderRadius.circular(10),
                    songId: snapshot.data![index].id,
                    type: ArtworkType.ALBUM,
                    path: '',
                    other:
                        "${snapshot.data?[index].getMap['album'] ?? 'Unknown'}",
                  ),
                ),
                openWidget: AlbumSongs(
                  albumId: snapshot.data![index].id,
                  album:
                      "${snapshot.data?[index].getMap['album'] ?? 'Unknown'}",
                  songs: snapshot.data![index].numOfSongs,
                ),
              ),
            ),
          );
        });
  }
}
