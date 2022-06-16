import 'dart:io';
import 'dart:ui';

// import 'package:app/music/body.dart';
import 'package:app/UI/player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_audio_query/flutter_audio_query.dart';
// import 'package:flutter_cube/flutter_cube.dart';

class AlbumMusic extends StatefulWidget {
  final String albumId;
  final String albumName;
  final ImageProvider<Object> artAlbum;
  const AlbumMusic({Key key, this.albumId, this.artAlbum, this.albumName})
      : super(key: key);

  @override
  _AlbumMusicState createState() => _AlbumMusicState();
}

class _AlbumMusicState extends State<AlbumMusic> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text("${widget.albumName}"),
      ),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
              image: DecorationImage(
            colorFilter: ColorFilter.mode(Colors.black54, BlendMode.darken),
            image: widget.artAlbum,
            fit: BoxFit.cover,
          )),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: FutureBuilder(
              future: FlutterAudioQuery().getSongsFromAlbum(
                albumId: widget.albumId,
              ),
              builder: (context, snapshot) {
                List<SongInfo> albumMusic = snapshot.data;
                if (snapshot.hasData)
                  return ListAlbum(tracks: albumMusic);
                else
                  return Container(
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                        Text("Loading Tracks"),
                      ],
                    ),
                  );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class ListAlbum extends StatefulWidget {
  final List<SongInfo> tracks;
  const ListAlbum({Key key, this.tracks}) : super(key: key);

  @override
  _ListAlbumState createState() => _ListAlbumState();
}

class _ListAlbumState extends State<ListAlbum> {
  Widget getAlbumArt(int value) {
    if (widget.tracks[value].albumArtwork == null)
      return CircleAvatar(
        radius: 25.0,
        backgroundImage: AssetImage("images/pAudio.jpeg"),
      );
    else {
      return CircleAvatar(
        radius: 25.0,
        backgroundImage: FileImage(File(widget.tracks[value].albumArtwork)),
      );
    }
  }

  Widget coverImage(int value) {
    if (widget.tracks[value].albumArtwork == null)
      return Image(
        fit: BoxFit.cover,
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height / 2,
        image: AssetImage("images/pAudio.jpeg"),
      );
    else {
      return Image(
        fit: BoxFit.cover,
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height / 2,
        image: FileImage(File(widget.tracks[value].albumArtwork)),
      );
    }
  }

  Widget trackList() {
    return ListView.separated(
        itemBuilder: (context, index) {
          return ListTile(
              leading: getAlbumArt(index),
              title: Text(
                "${widget.tracks[index].title}",
                style: TextStyle(
                  color: Colors.lightGreenAccent,
                  decorationStyle: TextDecorationStyle.solid,
                ),
              ),
              subtitle: Text(
                "${widget.tracks[index].artist}",
                style: TextStyle(color: Colors.lightGreen),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Player(
                      songs: widget.tracks,
                      jam: index,
                    ),
                  ),
                );
              });
        },
        separatorBuilder: (context, data) => Divider(),
        itemCount: widget.tracks.length);
  }

  @override
  Widget build(BuildContext context) {
    return trackList();
  }
}
