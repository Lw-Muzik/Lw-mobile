import 'dart:io';
import 'dart:ui';
// import 'package:app/music/search.dart';
import 'package:app/UI/player.dart';
import 'package:app/music/search.dart';
// import 'package:audioplayers/audio_cache.dart';
// import 'package:audioplayers/audioplayers.dart';
import 'package:equalizer/equalizer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
import 'package:flutter_audio_query/flutter_audio_query.dart';

// TextEditingController _controller = TextEditingController();
// bool playpause = false;
var background;
var image;
// int next;

class Songs extends StatefulWidget {
  final String bgImage;
  Songs({Key key, this.bgImage}) : super(key: key);

  @override
  _SongsState createState() => _SongsState();
}

class _SongsState extends State<Songs> {
  @override
  void initState() {
    super.initState();
    image = widget.bgImage;
    background = AssetImage("images/pAudio.jpeg");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () {
            Navigator.pop(context);
          },
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.orangeAccent,
          ),
        ),
        backgroundColor: Colors.black38,
        title: Text("All Songs", style: TextStyle(color: Colors.orangeAccent)),
      ),
      body: SafeArea(
        child: Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Colors.black87, BlendMode.darken),
                image: image != null ? FileImage(File(image)) : background,
              ),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 0.0, sigmaY: 0.0),
              child: FutureBuilder(
                  future: FlutterAudioQuery().getSongs(),
                  builder: (context, snapshot) {
                    List<SongInfo> tracks = snapshot.data;

                    if (snapshot.hasData)
                      return TrackBuilder(songs: tracks);
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
                                  "Loading Tracks",
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
                  }),
            )),
      ),
      floatingActionButton: FloatingActionButton(
        autofocus: true,
        onPressed: () {
          showCupertinoModalPopup(
            context: context,
            builder: (context) {
              return BottomSheet(
                onClosing: () {},
                builder: (context) {
                  return SearchTrack(file: image);
                },
              );
            },
          );
        },
        child: Icon(Icons.search_rounded, color: Colors.black),
        backgroundColor: Colors.orange[500],
      ),
    );
  }
}

class TrackBuilder extends StatefulWidget {
  final List<SongInfo> songs;
  const TrackBuilder({Key key, @required this.songs}) : super(key: key);

  @override
  _TrackBuilderState createState() => _TrackBuilderState();
}

class _TrackBuilderState extends State<TrackBuilder> {
  // AudioPlayer player = AudioPlayer();
  // AudioCache cached;
  // Duration musiclength = new Duration();
  // Duration position = new Duration();
  @override
  void initState() {
    super.initState();
    Equalizer.init(0);
    // SystemChrome.setEnabledSystemUIOverlays([SystemUiOverlay.top,SystemUiOverlay.bottom]);
    // cached = AudioCache(fixedPlayer: player);

    // // ignore: deprecated_member_use
    // player.durationHandler = (d) {
    //   setState(() {
    //     musiclength = d;
    //   });
    // };
    // // ignore: deprecated_member_use
    // player.positionHandler = (d) {
    //   setState(() {
    //     position = d;
    //   });
    // };

    // ignore: deprecated_member_use
    // player.seekCompleteHandler = (seek) {
    //   setState(() {
    //     if (seek) {
    //       next++;
    //     } else {}
    //   });
    // };
    // cached.load(url);
  }

  // void seekToSec(var sec) {
  //   setState(() {
  //     var posSec = Duration(seconds: sec.toInt());
  //     player.seek(posSec);
  //   });
  // }

  @override
  void dispose() {
    super.dispose();
    Equalizer.release();
  }

  // void nextTrack(int next) {
  //   setState(() {
  //     player.onSeekComplete;
  //     next++;
  //   });
  // }

  // double _progress = 0.0;
  // double _value = 10.0;
  String url;
  // void playPause() {
  //   setState(() => playpause = !playpause);
  // }

  Widget getAlbumArt(int value) {
    if (widget.songs[value].albumArtwork == null)
      return CircleAvatar(
        radius: 25.0,
        backgroundImage: AssetImage("images/pAudio.jpeg"),
      );
    else {
      return CircleAvatar(
        radius: 25.0,
        backgroundImage: FileImage(File(widget.songs[value].albumArtwork)),
      );
    }
  }

  Widget backImage(int value) {
    if (widget.songs[value].albumArtwork == null)
      return Card(
        color: Colors.transparent,
        elevation: 10,
        shadowColor: Colors.black,
        child: Container(
            padding: EdgeInsets.all(5.0),
            width: MediaQuery.of(context).size.width / 1.1,
            height: MediaQuery.of(context).size.height / 1.9,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              image: DecorationImage(
                fit: BoxFit.contain,
                image: AssetImage("images/pAudio.jpeg"),
              ),
            )),
      );
    else
      return Card(
        color: Colors.transparent,
        elevation: 18,
        shadowColor: Colors.black87,
        child: Container(
          padding: EdgeInsets.all(5.0),
          width: MediaQuery.of(context).size.width / 1.1,
          height: MediaQuery.of(context).size.height / 1.8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            image: DecorationImage(
              fit: BoxFit.contain,
              image: FileImage(File(widget.songs[value].albumArtwork)),
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemBuilder: (context, index) {
        return ListTile(
          leading: getAlbumArt(index),
          title: Text(widget.songs[index].title,
              style: TextStyle(color: Colors.white)),
          subtitle: Text(widget.songs[index].artist,
              style: TextStyle(color: Colors.white)),
          onTap: () async {
            // url = widget.songs[index].filePath;
            image = widget.songs[index].albumArtwork;
            Navigator.push(
              context,
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (context) => Player(
                  songs: widget.songs,
                  jam: index,
                ),
              ),
            );
          },
        );
      },
      separatorBuilder: (context, item) => Divider(
        color: Colors.white,
        thickness: 0.1,
      ),
      itemCount: widget.songs.length,
    );
  }
}
