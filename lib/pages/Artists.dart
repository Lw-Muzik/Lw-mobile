import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/extensions/index.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../widgets/ArtworkWidget.dart';
import 'ArtistSongs.dart';

class Artists extends StatefulWidget {
  const Artists({super.key});

  @override
  State<Artists> createState() => _ArtistsState();
}

class _ArtistsState extends State<Artists> {
  // ArtistModel z = ArtistModel(_info)
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.all(10),
      child: FutureBuilder<List<ArtistModel>>(
        // Default values:
        future: OnAudioQuery.platform.queryArtists(
          sortType: null,
          orderType: OrderType.ASC_OR_SMALLER,
          uriType: UriType.EXTERNAL,
          ignoreCase: true,
        ),

        builder: (context, item) {
          // Display error, if any.
          if (item.hasError) {
            return Text(item.error.toString());
          }

          // Waiting content.
          if (item.data == null) {
            return const CircularProgressIndicator();
          }

          // 'Library' is empty.
          if (item.data!.isEmpty) {
            return const Text("Nothing found!");
          }

          // You can use [item.data!] direct or you can create a:
          // List<SongModel> songs = item.data!;
          return GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 6),
            itemCount: item.data!.length,
            itemBuilder: (context, index) {
              Future.delayed(const Duration(seconds: 1));
              return Routes.animateTo(
                closedWidget: Container(
                  margin: const EdgeInsets.all(10),
                  child: GridTile(
                    footer: Card(
                      color: Theme.of(context).cardColor.withOpacity(0.4),
                      child: SizedBox(
                        height: 46,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "${item.data?[index].getMap['artist'] ?? 'Unknown'}",
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            Text(item.data![index].numberOfTracks!.nSongs,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleSmall),
                          ],
                        ),
                      ),
                    ),
                    // child: Container(),
                    child: ArtworkWidget(
                      borderRadius: BorderRadius.circular(10),
                      songId: item.data![index].id,
                      type: ArtworkType.ARTIST,
                      other:
                          "${item.data?[index].getMap['artist'] ?? 'Unknown'}",
                    ),
                  ),
                ),
                openWidget: ArtistSongs(
                  songs: item.data![index].numberOfTracks ?? 0,
                  albums: item.data![index].numberOfAlbums ?? 0,
                  artistId: item.data![index].id,
                  artist: "${item.data?[index].getMap['artist'] ?? 'Unknown'}",
                ),
              );
            },
          );
        },
      ),
    );
  }
}
