import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/extensions/index.dart';
import 'package:eq_app/pages/GenreSongs.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../widgets/ArtworkWidget.dart';

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
                            snapshot.data?[index].genre ?? 'Unknown',
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
                    type: ArtworkType.GENRE,
                    other: snapshot.data?[index].genre ?? 'Unknown',
                  ),
                ),
                openWidget: GenreSongs(
                  genreId: snapshot.data![index].id,
                  genre: snapshot.data![index].genre,
                  songs: snapshot.data![index].numOfSongs,
                ),
              ),
            ),
          );
        });
  }
}
