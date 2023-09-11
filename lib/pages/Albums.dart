import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/extensions/index.dart';
import 'package:eq_app/pages/AlbumSongs.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

class Albums extends StatefulWidget {
  const Albums({super.key});

  @override
  State<Albums> createState() => _AlbumsState();
}

class _AlbumsState extends State<Albums> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AlbumModel>>(
        stream: Stream.fromFuture(OnAudioQuery.platform.queryAlbums()),
        builder: (context, snapshot) {
          return GridView.count(
            crossAxisCount: 3,
            crossAxisSpacing: 26,
            mainAxisSpacing: 26,
            children: List.generate(
              snapshot.data?.length ?? 0,
              (index) => InkWell(
                onTap: () => Routes.routeTo(
                    AlbumSongs(
                      albumId: snapshot.data![index].id,
                      album: snapshot.data![index].album,
                    ),
                    context),
                child: GridTile(
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
                  child: QueryArtworkWidget(
                    artworkBorder: BorderRadius.circular(10),
                    id: snapshot.data![index].id,
                    type: ArtworkType.ALBUM,
                    nullArtworkWidget: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        "assets/audio.jpeg",
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        });
  }
}
