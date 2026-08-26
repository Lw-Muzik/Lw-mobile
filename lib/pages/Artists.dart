import '/Routes/routes.dart';
import '/extensions/index.dart';
import '/exports/exports.dart';
import '/data/library_repository.dart';
import '/controllers/library_controller.dart';

import '../widgets/artwork_widget.dart';
import '../widgets/library_list_row.dart';
import '../widgets/pinch_zoom_grid.dart';
import 'artist_songs.dart';

class Artists extends StatefulWidget {
  const Artists({super.key});

  @override
  State<Artists> createState() => _ArtistsState();
}

class _ArtistsState extends State<Artists> {
  late final Stream<List<ArtistModel>> _artistsStream;

  @override
  void initState() {
    super.initState();
    _artistsStream = context.read<LibraryRepository>().watchArtists();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: StreamBuilder<List<ArtistModel>>(
        stream: _artistsStream,
        builder: (context, item) {
          if (item.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          } else if (item.hasError) {
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
                    "Failed to load artists",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            );
          } else if (!item.hasData || item.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_off,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "No artists found",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            );
          }

          final artists = item.data!;
          final library = context.read<LibraryController>();
          return PinchZoomGrid(
            initialExtent: library.gridExtentFor('artists', fallback: 140.0),
            minExtent: 80.0,
            // Must exceed listModeExtent (260) or list mode is unreachable.
            maxExtent: 300.0,
            onExtentChanged: (e) => library.setGridExtent('artists', e),
            gridBuilder: (extent) => GridView.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: extent,
                crossAxisSpacing: 8,
                mainAxisSpacing: 12,
                childAspectRatio: 0.75,
              ),
              itemCount: artists.length,
              itemBuilder: (context, index) {
                final artist = artists[index];
                final artistName = "${artist.getMap['artist'] ?? 'Unknown'}";
                return InkWell(
                  onTap: () => Routes.scaleTo(
                    ArtistSongs(
                      songs: artist.numberOfTracks ?? 0,
                      albums: artist.numberOfAlbums ?? 0,
                      artistId: artist.id,
                      artist: artistName,
                    ),
                    context,
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: Hero(
                          tag: 'artist_${artist.id}',
                          child: ClipOval(
                            child: SizedBox.expand(
                              child: ArtworkWidget(
                                borderRadius: BorderRadius.zero,
                                width: double.infinity,
                                height: double.infinity,
                                songId: artist.id,
                                type: ArtworkType.ARTIST,
                                other: artistName,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        artistName,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(fontSize: 12),
                      ),
                      Text(
                        (artist.numberOfTracks ?? 0).nSongs,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              },
            ),
            listBuilder: ListView.builder(
              itemExtent: kLibraryRowExtent,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              itemCount: artists.length,
              itemBuilder: (context, index) {
                final artist = artists[index];
                final artistName = "${artist.getMap['artist'] ?? 'Unknown'}";
                return LibraryListRow(
                  title: artistName,
                  subtitle: '${artist.numberOfTracks ?? 0} tracks',
                  artworkId: artist.id,
                  artworkType: ArtworkType.ARTIST,
                  artworkName: artistName,
                  circular: true,
                  fallbackIcon: Icons.person_rounded,
                  onTap: () => Routes.scaleTo(
                    ArtistSongs(
                      songs: artist.numberOfTracks ?? 0,
                      albums: artist.numberOfAlbums ?? 0,
                      artistId: artist.id,
                      artist: artistName,
                    ),
                    context,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
