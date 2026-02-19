import '/exports/exports.dart';

import '/Routes/routes.dart';
import '/extensions/index.dart';
import 'package:eq_app/pages/AlbumSongs.dart';

import '../widgets/ArtworkWidget.dart';

class Albums extends StatefulWidget {
  const Albums({super.key});

  @override
  State<Albums> createState() => _AlbumsState();
}

class _AlbumsState extends State<Albums> {
  late Future<List<AlbumModel>> _albumsFuture;

  @override
  void initState() {
    super.initState();
    _albumsFuture = OnAudioQuery().queryAlbums();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AlbumModel>>(
      future: _albumsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        } else if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48,
                    color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 12),
                Text("Failed to load albums",
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          );
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.album, size: 64,
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                Text("No albums found",
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          );
        }

        final albums = snapshot.data!;
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.75,
            ),
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              final albumName =
                  "${album.getMap['album'] ?? 'Unknown'}";
              return InkWell(
                onTap: () => Routes.scaleTo(
                  AlbumSongs(
                    albumId: album.id,
                    album: albumName,
                    songs: album.numOfSongs,
                  ),
                  context,
                ),
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Hero(
                          tag: 'album_${album.id}',
                          child: SizedBox(
                            width: double.infinity,
                            child: ArtworkWidget(
                              borderRadius: BorderRadius.zero,
                              width: double.infinity,
                              height: double.infinity,
                              songId: album.id,
                              type: ArtworkType.ALBUM,
                              path: '',
                              other: albumName,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                        child: Text(
                          albumName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontSize: 13),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: Text(
                          album.numOfSongs.nSongs,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
