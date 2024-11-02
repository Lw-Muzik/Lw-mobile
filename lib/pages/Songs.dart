import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '/Helpers/Files.dart';
import 'ArtistSongs.dart';

class AllSongs extends StatefulWidget {
  const AllSongs({super.key});

  @override
  State<AllSongs> createState() => _AllSongsState();
}

class _AllSongsState extends State<AllSongs> {
  final ScrollController scrollController = ScrollController();

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SongModel>>(
      future: Files.fetchAllSongs(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        } else if (snap.hasError) {
          return Center(
            child: Text(
              "Failed to load songs. Please try again.",
              style: Theme.of(context).textTheme.titleMedium,
            ),
          );
        } else if (snap.hasData && snap.data!.isNotEmpty) {
          return SongLists(songs: snap.data!);
        } else {
          return Center(
            child: Text(
              "No songs available.",
              style: Theme.of(context).textTheme.titleMedium,
            ),
          );
        }
      },
    );
  }
}
