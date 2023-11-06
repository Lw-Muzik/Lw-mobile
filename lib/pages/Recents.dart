import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../Helpers/Files.dart';
import 'ArtistSongs.dart';

class Recents extends StatefulWidget {
  const Recents({super.key});

  @override
  State<Recents> createState() => _RecentsState();
}

class _RecentsState extends State<Recents> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SongModel>>(
      // Default values:
      future: Files.fetchMostRecentlyPlayed(),

      builder: (context, snap) {
        return snap.hasData
            ? SongLists(songs: snap.data ?? [])
            : const Center(child: CircularProgressIndicator.adaptive());
      },
    );
  }
}
