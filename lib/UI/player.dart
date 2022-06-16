import 'dart:io';
import 'dart:ui';

import 'package:audioplayers/audio_cache.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:equalizer/equalizer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';

void main() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
  runApp(Player());
}

class Player extends StatefulWidget {
  final int jam;
  final List songs;
  const Player({Key key, this.jam, this.songs}) : super(key: key);

  @override
  _PlayerState createState() => _PlayerState();
}

class _PlayerState extends State<Player> {
  AudioPlayer player = AudioPlayer();
  AudioCache cached;
  Duration musiclength = new Duration();
  Duration position = new Duration();

  int index;
  bool playpause = false;
  String url, title, nextTrac, artist;
  // new Visualizer();
  @override
  void initState() {
    super.initState();

    Equalizer.init(0);
    index = widget.jam;
    url = widget.songs[index].filePath;
    title = widget.songs[index].title;
    artist = widget.songs[index].artist;
    nextTrac = widget.songs[index].title;
    cached = AudioCache(fixedPlayer: player);
    // player.getAudioSessionId();
    player.play(url);
    // ignore: deprecated_member_use
    player.durationHandler = (d) {
      setState(() {
        musiclength = d;
      });
    };
    // ignore: deprecated_member_use
    player.positionHandler = (d) {
      setState(() {
        position = d;
      });
    };
// ignore: deprecated_member_use
    player.completionHandler = () {
      setState(() {
        index++;
        index > (widget.songs.length) || index == (widget.songs.length)
            ? player.stop()
            : player.play(widget.songs[index].filePath);
      });
      title = widget.songs[index].title;
      artist = widget.songs[index].artist;
      nextTrac = widget.songs[index + 1].title;
    };
    cached.load(url);
  }

  // void notify() async {
  //   player.setNotification(
  //       title: widget.songs[index].title, hasNextTrack: true);
  // }

  void seekToSec(var sec) {
    setState(() {
      var posSec = Duration(seconds: int.parse(sec));
      player.seek(posSec);
    });
  }

  bool view = true;
  @override
  void dispose() {
    super.dispose();
    Equalizer.release();
    player.release();
  }

  dynamic changeDuration(duration) {
    if (duration < 10) {
      return "0$duration";
    } else {
      return duration;
    }
  }

  bool selected = false;
  // double _progress = 0.0;
  double _value = 10.0;

  void playPause() {
    setState(() => playpause = !playpause);
  }

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
        shadowColor: Colors.black12,
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
        shadowColor: Colors.black,
        child: Container(
          padding: EdgeInsets.all(5.0),
          width: MediaQuery.of(context).size.width / 1.1,
          height: MediaQuery.of(context).size.height / 1.9,
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Container(
          padding: EdgeInsets.zero,
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          decoration: BoxDecoration(
            color: Colors.transparent,
            image: DecorationImage(
                fit: BoxFit.cover,
                image: widget.songs[index].albumArtwork == null
                    ? AssetImage("images/pAudio.jpeg")
                    : FileImage(File(widget.songs[index].albumArtwork))),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Column(
              children: [
                // SizedBox(height: 10,),
                Stack(
                  children: [
                    backImage(index),
                    Positioned(
                      bottom: 10,
                      left: 130,
                      child: Center(
                        child: CircleAvatar(
                          backgroundColor: Colors.black87,
                          child: IconButton(
                            onPressed: () {
                              showModalBottomSheet(
                                  backgroundColor: Colors.transparent,
                                  barrierColor: Colors.black.withOpacity(0.7),
                                  context: context,
                                  builder: (context) {
                                    return Container(
                                      padding: EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                          color: Colors.black87,
                                          borderRadius: BorderRadius.only(
                                            topLeft: Radius.circular(10),
                                            topRight: Radius.circular(10),
                                          )),
                                      child: ListView.separated(
                                          itemBuilder: (context, list) {
                                            return ListTile(
                                              // autofocus: true,
                                              selected: selected,
                                              focusColor:
                                                  Colors.lightBlueAccent,
                                              title: Text(
                                                widget.songs[list].title,
                                                style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w400,
                                                    color: Colors.orangeAccent),
                                              ),
                                              leading: getAlbumArt(list),
                                              onTap: () {
                                                setState(() => index = list);
                                                Navigator.pop(context);
                                                url =
                                                    widget.songs[list].filePath;
                                                player.play(url);
                                                // Title
                                                title =
                                                    widget.songs[list].title;
                                                // Artist
                                                artist =
                                                    widget.songs[list].artist;
                                              },
                                            );
                                          },
                                          separatorBuilder: (context, dt) =>
                                              Divider(),
                                          itemCount: widget.songs.length),
                                    );
                                  });
                            },
                            icon: Icon(
                              Icons.playlist_play_rounded,
                              color: Colors.orangeAccent,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Center(
                        child: Container(
                          height: 28,
                          padding: EdgeInsets.zero,
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Visibility(
                            visible: view,
                            child: TextButton(
                              onPressed: () {
                                setState(() {
                                  view = !view;
                                });
                              },
                              child: Text(
                                "Tracks ($index / ${widget.songs.length})",
                                style: TextStyle(
                                    color: Colors.orangeAccent,
                                    fontFamily: "Arial",
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14),
                              ),
                            ),
                            replacement: TextButton(
                              onPressed: () {
                                setState(() {
                                  view = !view;
                                });
                              },
                              child: Text(
                                "Next: $title",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w300,
                                    fontFamily: "Arial",
                                    fontSize: 13),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: CircleAvatar(
                        backgroundColor: Colors.black.withOpacity(0.7),
                        child: IconButton(
                          color: Colors.orangeAccent,
                          onPressed: () {
                            setState(() {
                              // showMenu(context: context, position: position, items: items)
                              showCupertinoModalPopup(
                                filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                                context: context,
                                builder: (context) {
                                  return BottomSheet(
                                    onClosing: () {},
                                    enableDrag: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (context) {
                                      return Container(
                                        padding: EdgeInsets.all(15),
                                        height:
                                            MediaQuery.of(context).size.height /
                                                1.6,
                                        decoration: BoxDecoration(
                                            color:
                                                Colors.black.withOpacity(0.8),
                                            borderRadius: BorderRadius.only(
                                                topLeft: Radius.circular(20),
                                                topRight: Radius.circular(20))),
                                        child: Column(
                                          children: [
                                            ListTile(
                                              leading: Icon(
                                                Icons.volume_down_rounded,
                                                size: 30,
                                                color: Colors.orangeAccent,
                                              ),
                                              title: Text(
                                                "Change volume",
                                                style: TextStyle(
                                                    color: Colors.orangeAccent,
                                                    fontSize: 17),
                                              ),
                                              subtitle: SfSlider(
                                                  activeColor:
                                                      Colors.orangeAccent,
                                                  inactiveColor: Colors.white,
                                                  // showTicks: true,
                                                  // showLabels: true,
                                                  stepSize: 2,
                                                  enableTooltip: true,
                                                  minorTicksPerInterval: 0,
                                                  value: _value,
                                                  min: 0.0,
                                                  // interval: 20,
                                                  max: 5,
                                                  onChanged: (volume) {
                                                    setState(() {
                                                      _value = volume;
                                                      player.setVolume(_value);
                                                    });
                                                  }),
                                            ),
                                            Divider(
                                              color: Colors.orangeAccent,
                                              thickness: 0.2,
                                            ),
                                            ListTile(
                                              leading: Icon(
                                                Icons.equalizer_rounded,
                                                size: 30,
                                                color: Colors.orangeAccent,
                                              ),
                                              title: Text(
                                                "Equalizer",
                                                style: TextStyle(
                                                  color: Colors.orangeAccent,
                                                  fontWeight: FontWeight.w400,
                                                  fontSize: 17,
                                                ),
                                              ),
                                              onTap: () {
                                                Navigator.pop(context);
                                                Equalizer.open(0);
                                              },
                                            ),
                                            Divider(
                                              color: Colors.orangeAccent,
                                              thickness: 0.2,
                                            ),
                                            ListTile(
                                              leading: Icon(
                                                Icons.graphic_eq_rounded,
                                                size: 30,
                                                color: Colors.orangeAccent,
                                              ),
                                              title: Text(
                                                "Visualizers",
                                                style: TextStyle(
                                                  color: Colors.orangeAccent,
                                                  fontWeight: FontWeight.w400,
                                                  fontSize: 17,
                                                ),
                                              ),
                                              onTap: () {
                                                Navigator.pop(context);
                                                // Navigator.push(
                                                //   context,
                                                //   MaterialPageRoute(
                                                //       builder: (context) =>
                                                //           Visual(),
                                                //       fullscreenDialog: true),
                                                // );
                                              },
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                              );
                            });
                          },
                          icon: Icon(Icons.settings),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      left: 10,
                      child: CircleAvatar(
                        backgroundColor: Colors.black87,
                        child: IconButton(
                          color: Colors.orangeAccent,
                          onPressed: () {},
                          icon: Icon(Icons.shuffle_rounded),
                        ),
                      ),
                    )
                  ],
                ),
                // SnackBarAction(label: "Long press", onPressed: () {}),
                // SnackBar(content: Text("Long Press here")),
                Center(
                  child: Container(
                    padding: EdgeInsets.all(5),
                    decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w300),
                        ),
                        Text(
                          artist,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w300),
                        ),
                      ],
                    ),
                  ),
                ),

                Padding(
                  padding: EdgeInsets.all(2),
                  child: Slider(
                    activeColor: Colors.orangeAccent,
                    inactiveColor: Colors.black87,
                    value: position.inSeconds.toDouble(),
                    max: musiclength.inSeconds.toDouble(),
                    min: 0.0,
                    onChanged: (value) {
                      // setState(() => player.onAudioPositionChanged);
                      seekToSec(value);
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: <Widget>[
                      CircleAvatar(
                        backgroundColor: Colors.black87,
                        child: IconButton(
                          onPressed: () {
                            setState(() {
                              if (index == 0 || index < 0) {
                                player.stop();
                                index = 0;
                              } else {
                                index--;
                              }

                              player.play(widget.songs[index].filePath);
                            });
                          },
                          icon: Icon(
                            Icons.fast_rewind_rounded,
                            color: Colors.orangeAccent,
                          ),
                        ),
                      ),
                      Visibility(
                        visible: playpause,
                        child: CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.black87,
                          child: IconButton(
                            iconSize: 40,
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.orangeAccent,
                            ),
                            onPressed: () {
                              player.resume();
                              setState(() => playpause = false);
                            },
                          ),
                        ),
                        replacement: CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.black87,
                          child: IconButton(
                              padding: EdgeInsets.zero,
                              iconSize: 40,
                              onPressed: () {
                                player.pause();
                                setState(() {
                                  playpause = true;
                                });
                              },
                              icon: Icon(
                                Icons.pause_rounded,
                                color: Colors.orangeAccent,
                              )),
                        ),
                      ),
                      CircleAvatar(
                        backgroundColor: Colors.black87,
                        child: IconButton(
                          onPressed: () {
                            setState(() {
                              if (index == (widget.songs.length) ||
                                  index > (widget.songs.length)) {
                                player.stop();
                                index = 0;
                              } else {
                                index++;
                                player.play(widget.songs[index].filePath);
                              }
                            });
                          },
                          icon: Icon(
                            Icons.fast_forward_rounded,
                            color: Colors.orangeAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 0,
                ),
                Center(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "${position.inMinutes}:${changeDuration(position.inSeconds.remainder(60))}",
                          style: TextStyle(
                            color: Colors.orangeAccent,
                            fontFamily: "Arial",
                            fontSize: 17,
                          ),
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "${musiclength.inMinutes}:${changeDuration(musiclength.inSeconds.remainder(60))}",
                          style: TextStyle(
                              color: Colors.orangeAccent,
                              fontFamily: "Arial",
                              fontSize: 17),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
