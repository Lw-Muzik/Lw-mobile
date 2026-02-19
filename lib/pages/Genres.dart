import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/extensions/index.dart';
import 'package:eq_app/pages/GenreSongs.dart';
import '/exports/exports.dart';

import '../widgets/ArtworkWidget.dart';

class Genres extends StatefulWidget {
  const Genres({super.key});

  @override
  State<Genres> createState() => _GenresState();
}

class _GenresState extends State<Genres> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GenreModel>>(
      future: OnAudioQuery.platform.queryGenres(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return const Center(child: Text("Error loading genres"));
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text("No genres found"));
        }

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: GridView.builder(
            itemCount: snapshot.data!.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
            ),
            itemBuilder: (context, index) {
              final genre = snapshot.data![index];
              return Routes.animateTo(
                closedWidget: GridTile(
                  footer: Card(
                    color: Theme.of(context).cardColor.withValues(alpha: 0.4),
                    child: SizedBox(
                      height: 46,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            genre.genre,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          Text(
                            genre.numOfSongs.nSongs,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  child: ArtworkWidget(
                    borderRadius: BorderRadius.circular(10),
                    songId: genre.id,
                    type: ArtworkType.GENRE,
                    other: genre.genre,
                  ),
                ),
                openWidget: GenreSongs(
                  genreId: genre.id,
                  genre: genre.genre,
                  songs: genre.numOfSongs,
                ),
              );
            },
          ),
        );
      },
    );
  }
}
