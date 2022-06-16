import 'dart:io';
import 'dart:ui';

// import 'package:app/UI/player.dart';
import 'package:app/UI/player.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_audio_query/flutter_audio_query.dart';

var background = AssetImage("images/pAudio.jpeg");
var image;

class SearchTrack extends StatefulWidget {
  final String file;
  // List<SongInfo> trackList;
  SearchTrack({Key key, this.file}) : super(key: key);

  @override
  _SearchTrackState createState() => _SearchTrackState();
}

class _SearchTrackState extends State<SearchTrack> {
  final fieldController = TextEditingController();
  @override
  void initState() {
    super.initState();
    image = widget.file;
  }

  void dispose() {
    fieldController.dispose();
    super.dispose();
  }

  var results = "Track";
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
          elevation: 0,
          shadowColor: Colors.transparent,
          actions: [
            IconButton(
                onPressed: () {
                  fieldController.clear();
                },
                icon: Icon(Icons.clear, color: Colors.orangeAccent))
          ],
          backgroundColor: Colors.black,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_rounded,
              color: Colors.orangeAccent,
            ),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          title: CupertinoTextField(
            controller: fieldController,
            placeholder: "Enter name of the track",
            padding: EdgeInsets.all(10),
            keyboardType: TextInputType.text,
            autocorrect: true,
            autofocus: true,
            onChanged: (value) {
              setState(() {
                results = fieldController.text;
              });
            },
            onEditingComplete: () {},
          )),
      body: FutureBuilder(
          future: FlutterAudioQuery().searchSongs(query: results),
          builder: (context, snapshot) {
            List<SongInfo> search = snapshot.data;
            if (snapshot.hasData)
              return SearchResults(result: search);
            else
              return Padding(
                padding: const EdgeInsets.only(top: 240),
                child: Center(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(15),
                        child: Text(
                          "$results Not found",
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
    );
  }
}

class SearchResults extends StatefulWidget {
  final List<SongInfo> result;

  const SearchResults({Key key, this.result}) : super(key: key);

  @override
  _SearchResultsState createState() => _SearchResultsState();
}

class _SearchResultsState extends State<SearchResults> {
  Widget getAlbumArt(int value) {
    if (widget.result[value].albumArtwork == null)
      return CircleAvatar(
        radius: 30,
        backgroundColor: Colors.transparent,
        backgroundImage: AssetImage("images/default.png"),
      );
    else
      return CircleAvatar(
        radius: 30,
        backgroundColor: Colors.transparent,
        backgroundImage: FileImage(
          File(widget.result[value].albumArtwork),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
          image: DecorationImage(
              colorFilter: ColorFilter.mode(Colors.black87, BlendMode.darken),
              image: image != null ? FileImage(File(image)) : background,
              fit: BoxFit.cover),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          child: ListView.separated(
            itemBuilder: (context, index) {
              return ListTile(
                leading: getAlbumArt(index),
                title: Text(
                  widget.result[index].title,
                  style: TextStyle(color: Colors.greenAccent),
                ),
                subtitle: Text(
                  widget.result[index].artist,
                  style: TextStyle(color: Colors.greenAccent),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Player(
                        songs: widget.result,
                        jam: index,
                      ),
                    ),
                  );
                },
              );
            },
            separatorBuilder: (context, item) => Divider(
              color: Colors.lightGreenAccent,
              thickness: 0.2,
            ),
            itemCount: widget.result.length,
          ),
        ));
  }
}
