import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

class Genres extends StatefulWidget {
  const Genres({super.key});

  @override
  State<Genres> createState() => _GenresState();
}

class _GenresState extends State<Genres> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GenreModel>>(
        stream: Stream.fromFuture(OnAudioQuery.platform.queryGenres()),
        builder: (context, snapshot) {
          return GridView.count(
            crossAxisCount: 3,
            crossAxisSpacing: 26,
            mainAxisSpacing: 26,
            children: List.generate(
              snapshot.data?.length ?? 0,
              (index) => GridTile(
                footer: Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(top: 100),
                  child: Text(
                    "${snapshot.data?[index].numOfSongs} Songs",
                    textAlign: TextAlign.center,
                  ),
                ),
                child: QueryArtworkWidget(
                  id: snapshot.data![index].id,
                  type: ArtworkType.GENRE,
                ),
              ),
            ),
          );
        });
  }
}
