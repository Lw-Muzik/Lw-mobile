import 'package:flutter/material.dart';

class OnlinePlaylist extends StatefulWidget {
  const OnlinePlaylist({super.key});

  @override
  State<OnlinePlaylist> createState() => _OnlinePlaylistState();
}

class _OnlinePlaylistState extends State<OnlinePlaylist> {
  @override
  Widget build(BuildContext context) {
    return NestedScrollView(
      headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
        return [];
      },
      body: Scaffold(
        body: Center(
          child: Text("Playlist"),
        ),
      ),
    );
  }
}
