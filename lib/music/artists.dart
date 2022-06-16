import 'dart:io';

import 'package:app/music/artMusic.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_audio_query/flutter_audio_query.dart';
import 'package:just_audio/just_audio.dart';

class Artists extends StatefulWidget {
  @override
  _ArtistsState createState() => _ArtistsState();
}

class _ArtistsState extends State<Artists> {
  var player = AudioPlayer();
  @override
  void initState() {
    super.initState();
    print(player.androidAudioSessionId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        // shape: BeveledRectangleBorder(
        //   side: BorderSide(width: 1),
        //   borderRadius: BorderRadius.all(Radius.circular(60)),
        // ),
        backgroundColor: Colors.black12,
        shadowColor: Colors.black12,
        title: Text("Artist"),
      ),
      body: SafeArea(
        child: FutureBuilder(
          future: FlutterAudioQuery().getArtists(),
          // ignore: missing_return
          builder: (context, AsyncSnapshot snapshot) {
            List<ArtistInfo> jams = snapshot.data;
            if (snapshot.hasData)
              return LoadArtist(albums: jams);
            else
              return Padding(
                padding: const EdgeInsets.only(top: 240),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      Padding(
                        padding: const EdgeInsets.all(15),
                        child: Text(
                          "Loading Artists",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
          },
        ),
      ),
    );
  }
}

class LoadArtist extends StatefulWidget {
  final List<ArtistInfo> albums;
  const LoadArtist({Key key, this.albums}) : super(key: key);
  @override
  _LoadArtistState createState() => _LoadArtistState();
}

class _LoadArtistState extends State<LoadArtist> {
  int flag;
  @override
  void initState() {
    super.initState();
    setState(() => flag = 0);
  }

  // ignore: non_constant_identifier_names
  ImageProvider<Object> LoadAssets(int asset) {
    if (widget.albums[asset].artistArtPath == null)
      return AssetImage("images/pAudio.jpeg");
    else
      return FileImage(File(widget.albums[asset].artistArtPath));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.88), BlendMode.darken),
          image: LoadAssets(1),
        ),
      ),
      child: ListView.separated(
          itemBuilder: (context, index) {
            // setState(() => flag);
            return ListTile(
              leading: CircleAvatar(
                radius: 35,
                backgroundImage: LoadAssets(index),
              ),
              title: Text(
                widget.albums[index].name,
                style: TextStyle(color: Colors.orangeAccent),
              ),
              subtitle: Text(
                "Tracks (${widget.albums[index].numberOfTracks})  -  Albums (${widget.albums[index].numberOfAlbums})",
                style: TextStyle(color: Colors.orangeAccent),
              ),
              onTap: () {
                var _artistId = widget.albums[index].id;
                var _artistName = widget.albums[index].name;
                var _artistArt = widget.albums[index].artistArtPath == null
                    ? AssetImage('images/pAudio.jpeg')
                    : FileImage(
                        File(widget.albums[index].artistArtPath),
                      );
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ArtMusic(
                      artistId: _artistId,
                      artistArt: _artistArt,
                      artistName: _artistName,
                    ),
                  ),
                );
              },
            );
          },
          separatorBuilder: (context, data) => Divider(
                color: Colors.orangeAccent,
                thickness: 0.21,
              ),
          itemCount: widget.albums.length),
    );
  }
}
