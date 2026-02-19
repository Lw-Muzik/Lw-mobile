import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/extensions/index.dart';
import '/exports/exports.dart';

import '../widgets/ArtworkWidget.dart';
import 'ArtistSongs.dart';

class Artists extends StatefulWidget {
  const Artists({super.key});

  @override
  State<Artists> createState() => _ArtistsState();
}

class _ArtistsState extends State<Artists> {
  late Future<List<ArtistModel>> _artistsFuture;

  @override
  void initState() {
    super.initState();
    _artistsFuture = OnAudioQuery.platform.queryArtists(
      sortType: null,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: FutureBuilder<List<ArtistModel>>(
        future: _artistsFuture,
        builder: (context, item) {
          if (item.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          } else if (item.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 12),
                  Text("Failed to load artists",
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            );
          } else if (!item.hasData || item.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_off, size: 64,
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text("No artists found",
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            );
          }

          final artists = item.data!;
          return GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 12,
              childAspectRatio: 0.75,
            ),
            itemCount: artists.length,
            itemBuilder: (context, index) {
              final artist = artists[index];
              final artistName =
                  "${artist.getMap['artist'] ?? 'Unknown'}";
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 12,
                      ),
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
          );
        },
      ),
    );
  }
}
