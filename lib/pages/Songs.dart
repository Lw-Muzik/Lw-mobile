import '/Helpers/Files.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'ArtistSongs.dart';

class AllSongs extends StatefulWidget {
  const AllSongs({super.key});

  @override
  State<AllSongs> createState() => _AllSongsState();
}

class _AllSongsState extends State<AllSongs> {
  ScrollController scrollController = ScrollController();
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SongModel>>(
      // Default values:
      future: Files.fetchAllSongs(),

      builder: (context, snap) {
        return snap.hasData
            ? SongLists(songs: snap.data ?? [])
            : const Center(child: CircularProgressIndicator.adaptive());
      },
    );
  }
}
