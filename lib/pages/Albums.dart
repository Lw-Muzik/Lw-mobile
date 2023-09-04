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
              (index) => GridTile(
                footer: Card(
                  child: Center(
                    child: Text("${snapshot.data?[index].numOfSongs} Songs",
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ),
                child: QueryArtworkWidget(
                  id: snapshot.data![index].id,
                  type: ArtworkType.ALBUM,
                  nullArtworkWidget: ClipRRect(
                    borderRadius: BorderRadius.circular(50),
                    child: Image.asset("assets/audio.jpeg"),
                  ),
                ),
              ),
            ),
          );
        });
  }
}
