import 'dart:io';
import 'dart:ui';
import 'package:app/music/albumMusic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_audio_query/flutter_audio_query.dart';

class Albums extends StatefulWidget {
  @override
  _Album createState() => _Album();
}

class _Album extends State<Albums> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green[900],
        leading: IconButton(
          color: Colors.orangeAccent,
          onPressed: () {
            Navigator.pop(context);
          },
          icon: Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: Text(
          "Albums",
          style: TextStyle(
            color: Colors.orangeAccent,
          ),
        ),
      ),
      backgroundColor: Colors.transparent,
      body: SafeArea(
          child: FutureBuilder(
              future: FlutterAudioQuery().getAlbums(),
              // ignore: missing_return
              builder: (context, AsyncSnapshot snapshot) {
                List<AlbumInfo> jams = snapshot.data;
                if (snapshot.hasData) if (jams.length == null)
                  return Center(
                    child: Container(
                      child: Text("No Albums found"),
                    ),
                  );
                else
                  return LoadAlbum(albums: jams);
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
                              "Loading Albums",
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
              })),
    );
  }
}

Widget loadImages(int load, var widget) {
  if (widget.albums[load].albumArt == null) {
    return Image(image: AssetImage("images/pAudio.jpeg"));
  } else {
    return Image.file(File(widget.albums[load].albumArt));
  }
}

class LoadAlbum extends StatefulWidget {
  final List<AlbumInfo> albums;
  const LoadAlbum({Key key, this.albums}) : super(key: key);
  @override
  _LoadAlbumState createState() => _LoadAlbumState();
}

class _LoadAlbumState extends State<LoadAlbum> {
  // ignore: non_constant_identifier_names
  ImageProvider<Object> LoadAssets(int asset) {
    if (widget.albums[asset].albumArt == null)
      return AssetImage("images/pAudio.jpeg");
    else
      return FileImage(File(widget.albums[asset].albumArt));
  }

  var _albumId;
  var _artAlbum;
  var _albumName;
  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage("images/pAudio.jpeg"),
            colorFilter: ColorFilter.mode(Colors.black54, BlendMode.darken),
            fit: BoxFit.cover,
          ),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 17,
            sigmaY: 17,
          ),
          child: ListView.separated(
              itemBuilder: (context, index) {
                return ListTile(
                    leading: CircleAvatar(
                      radius: 30,
                      backgroundImage: LoadAssets(index),
                    ),
                    title: Text(
                      "${widget.albums[index].title}",
                      style: TextStyle(
                        color: Colors.lightGreenAccent,
                        decorationStyle: TextDecorationStyle.solid,
                      ),
                    ),
                    subtitle: Text(
                      "Tracks (${widget.albums[index].numberOfSongs})",
                      style: TextStyle(color: Colors.lightGreen),
                    ),
                    onTap: () {
                      _albumId = widget.albums[index].id;
                      _albumName = widget.albums[index].title;
                      _artAlbum = widget.albums[index].albumArt == null
                          ? AssetImage("images/pAudio.jpeg")
                          : FileImage(File(widget.albums[index].albumArt));
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          fullscreenDialog: true,
                          builder: (context) => AlbumMusic(
                            albumId: _albumId,
                            albumName: _albumName,
                            artAlbum: _artAlbum,
                          ),
                        ),
                      );
                    });
              },
              separatorBuilder: (context, data) => Divider(),
              itemCount: widget.albums.length),
        ));
  }
}

// class AlbumMusic extends StatefulWidget {
//   final List<SongInfo> music;
//   const AlbumMusic({Key key, this.music}) : super(key: key);
//   @override
//   _AlbumMusicState createState() => _AlbumMusicState();
// }

// class _AlbumMusicState extends State<AlbumMusic> {
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       width: MediaQuery.of(context).size.width,
//       height: MediaQuery.of(context).size.height,
//       child: BackdropFilter(
//         filter: ImageFilter.blur(
//           sigmaX: 17,
//           sigmaY: 17,
//         ),
//         child: ListView.separated(
//             itemBuilder: (context, data) {
//               return ListTile(
//                 leading: loadImages(data, widget),
//                 title: Text(widget.music[data].title),
//               );
//             },
//             separatorBuilder: (context, data) => Divider(),
//             itemCount: widget.music.length),
//       ),
//     );
//   }
// }
