import 'dart:io';

import 'package:app/UI/player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_audio_query/flutter_audio_query.dart';

class ArtMusic extends StatefulWidget {
  final String artistId;
  final String artistName;
  final ImageProvider<Object> artistArt;
  const ArtMusic({Key key, this.artistArt, this.artistId, this.artistName})
      : super(key: key);

  @override
  _ArtMusicState createState() => _ArtMusicState();
}

class _ArtMusicState extends State<ArtMusic> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black12,
      appBar: AppBar(
        backgroundColor: Colors.black12,
        title: Text(
          widget.artistName,
        ),
      ),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(Colors.black87, BlendMode.darken),
              image: widget.artistArt,
            ),
          ),
          child: FutureBuilder(
            future: FlutterAudioQuery()
                .getSongsFromArtist(artistId: widget.artistName),
            builder: (context, snapshot) {
              List<SongInfo> songs = snapshot.data;
              return snapshot.hasData
                  ? MusicArt(songs: songs)
                  : Container(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).size.height / 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          Text(
                            'Loading Music from Artist Info',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    );
            },
          ),
        ),
      ),
    );
  }
}

class MusicArt extends StatefulWidget {
  final List<SongInfo> songs;
  const MusicArt({Key key, this.songs}) : super(key: key);

  @override
  _MusicArtState createState() => _MusicArtState();
}

class _MusicArtState extends State<MusicArt> {
  // ignore: non_constant_identifier_names
  ImageProvider<Object> LoadAssets(int asset) {
    if (widget.songs[asset].albumArtwork == null)
      return AssetImage("images/pAudio.jpeg");
    else
      return FileImage(File(widget.songs[asset].albumArtwork));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      child: ListView.separated(
        itemBuilder: (context, index) {
          return ListTile(
            leading: CircleAvatar(
              radius: 35,
              backgroundImage: LoadAssets(index),
            ),
            title: Text(
              widget.songs[index].title,
              style: TextStyle(color: Colors.amber),
            ),
            subtitle: Text(
              '${widget.songs[index].artist} - ${widget.songs[index].album}',
              style: TextStyle(color: Colors.amber),
            ),
            onTap: () {
              var _songs = widget.songs;
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => Player(
                            jam: index,
                            songs: _songs,
                          )));
            },
          );
        },
        separatorBuilder: (context, data) => Divider(),
        itemCount: widget.songs.length,
      ),
    );
  }
}
