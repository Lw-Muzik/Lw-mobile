import 'package:eq_app/Routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'ArtistSongs.dart';

class Artists extends StatefulWidget {
  const Artists({super.key});

  @override
  State<Artists> createState() => _ArtistsState();
}

class _ArtistsState extends State<Artists> {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FutureBuilder<List<ArtistModel>>(
        // Default values:
        future: _audioQuery.queryArtists(
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
                crossAxisCount: 3, crossAxisSpacing: 26, mainAxisSpacing: 26),
            itemCount: item.data!.length,
            itemBuilder: (context, index) {
              return InkWell(
                onTap: () {
                  Routes.routeTo(
                      ArtistSongs(
                        artistId: item.data![index].id,
                        artist:
                            "${item.data?[index].getMap['artist'] ?? 'Unknown'}",
                      ),
                      context,
                      animate: true);
                },
                child: GridTile(
                  footer: Card(
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
                          Text("${item.data?[index].numberOfTracks} Songs",
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleSmall),
                        ],
                      ),
                    ),
                  ),
                  child: QueryArtworkWidget(
                    artworkBorder: BorderRadius.circular(10),
                    format: ArtworkFormat.PNG,
                    size: 500,
                    controller: _audioQuery,
                    id: item.data![index]?.id ?? 0,
                    nullArtworkWidget: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset("assets/audio.jpeg"),
                    ),
                    type: ArtworkType.ARTIST,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
