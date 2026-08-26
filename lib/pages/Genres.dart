import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/extensions/index.dart';
import 'package:eq_app/pages/genre_songs.dart';
import '/exports/exports.dart';
import '/data/library_repository.dart';
import '/controllers/library_controller.dart';

import '../widgets/library_list_row.dart';
import '../widgets/pinch_zoom_grid.dart';

class Genres extends StatefulWidget {
  const Genres({super.key});

  @override
  State<Genres> createState() => _GenresState();
}

class _GenresState extends State<Genres> {
  late final Stream<List<GenreModel>> _genresStream;

  @override
  void initState() {
    super.initState();
    _genresStream = context.read<LibraryRepository>().watchGenres();
  }

  Color _genreColor(String name) {
    final hash = name.hashCode;
    final hue = (hash % 360).abs().toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.5, 0.35).toColor();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GenreModel>>(
      stream: _genresStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        } else if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  "Failed to load genres",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          );
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.category,
                  size: 64,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 12),
                Text(
                  "No genres found",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          );
        }

        final genres = snapshot.data!;
        final library = context.read<LibraryController>();
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: PinchZoomGrid(
            initialExtent: library.gridExtentFor('genres', fallback: 200.0),
            minExtent: 100.0,
            maxExtent: 300.0,
            onExtentChanged: (e) => library.setGridExtent('genres', e),
            gridBuilder: (extent) => GridView.builder(
              itemCount: genres.length,
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: extent,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemBuilder: (context, index) {
                final genre = genres[index];
                final baseColor = _genreColor(genre.genre);
                return InkWell(
                  onTap: () => Routes.scaleTo(
                    GenreSongs(
                      genreId: genre.id,
                      genre: genre.genre,
                      songs: genre.numOfSongs,
                    ),
                    context,
                  ),
                  child: Hero(
                    tag: 'genre_${genre.id}',
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              baseColor,
                              baseColor.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.music_note,
                              size: 36,
                              color: Colors.white70,
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Text(
                                genre.genre,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(color: Colors.white),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                genre.numOfSongs.nSongs,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            listBuilder: ListView.builder(
              itemExtent: kLibraryRowExtent,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              itemCount: genres.length,
              itemBuilder: (context, index) {
                final genre = genres[index];
                return LibraryListRow(
                  title: genre.genre,
                  subtitle: '${genre.numOfSongs} songs',
                  artworkId: null,
                  fallbackIcon: Icons.library_music_rounded,
                  onTap: () => Routes.scaleTo(
                    GenreSongs(
                      genreId: genre.id,
                      genre: genre.genre,
                      songs: genre.numOfSongs,
                    ),
                    context,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
