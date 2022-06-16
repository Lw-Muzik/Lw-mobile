import 'dart:ui';

import 'package:drawer_swipe/drawer_swipe.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'music/albums.dart';
import 'music/artists.dart';
import 'music/playlist.dart';
import 'music/songs.dart';

class Home extends StatefulWidget {
  @override
  _Home createState() => _Home();
}

class _Home extends State<Home> with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
  }

  GlobalKey<SwipeDrawerState> drawerkey = GlobalKey<SwipeDrawerState>();
  // GlobalKey btn = GlobalKey();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      // backgroundColor: Colors,
      body: SwipeDrawer(
        radius: 10,
        child: buildBody(),
        drawer: buildDrawer(),
        key: drawerkey,
        backgroundColor: Colors.black12,
        curve: Curves.bounceInOut,
      ),
    );
  }

  Widget buildBody() {
    return NestedScrollView(
      scrollDirection: Axis.horizontal,
      headerSliverBuilder: (context, id) {
        return <Widget>[
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverAppBar(
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      colorFilter: ColorFilter.mode(
                        Colors.black,
                        BlendMode.darken,
                      ),
                      fit: BoxFit.cover,
                      image: AssetImage("images/quin.jpg"),
                    ),
                  ),
                ),
                title: Text(
                  "Library",
                  style: Theme.of(context).textTheme.headline5.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w200,
                      ),
                ),
                centerTitle: true,
              ),
              backgroundColor: Colors.black,
              expandedHeight: 250,
              pinned: false,
              leading: InkWell(
                child: Icon(Icons.list),
                onTap: () {
                  if (drawerkey.currentState.isOpened()) {
                    drawerkey.currentState.closeDrawer();
                  } else {
                    drawerkey.currentState.openDrawer();
                  }
                },
              ),
              systemOverlayStyle: SystemUiOverlayStyle.light,
            ),
          )
        ];
      },
      body: Center(
        child: bodyLib(),
      ),
    );
  }

//Library body
  Widget bodyLib() {
    return Container(
      decoration: BoxDecoration(
          color: Colors.transparent,
          image: DecorationImage(
              colorFilter: ColorFilter.mode(
                Colors.black,
                BlendMode.darken,
              ),
              image: AssetImage("images/quin.jpg"),
              fit: BoxFit.cover)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
        child: SafeArea(
          child: ListView(
            children: [
              ListTile(
                leading: Icon(
                  Icons.music_note_rounded,
                  color: Colors.orangeAccent,
                ),
                title: Text("All Songs",
                    style: TextStyle(
                      color: Colors.orangeAccent,
                    )),
                onTap: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => Songs(),
                        fullscreenDialog: true,
                      ));
                },
              ),
              Divider(),
              ListTile(
                leading: Icon(Icons.album_rounded, color: Colors.orangeAccent),
                title: Text("Albums",
                    style: TextStyle(
                      color: Colors.orangeAccent,
                    )),
                onTap: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => Albums(),
                        fullscreenDialog: true,
                      ));
                },
              ),
              Divider(),
              ListTile(
                leading: Icon(Icons.speaker_group_rounded,
                    color: Colors.orangeAccent),
                title: Text("Artists",
                    style: TextStyle(
                      color: Colors.orangeAccent,
                    )),
                onTap: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => Artists(),
                        fullscreenDialog: true,
                      ));
                },
              ),
              Divider(),
              ListTile(
                leading: Icon(Icons.playlist_play_rounded,
                    color: Colors.orangeAccent),
                title: Text("Playlists",
                    style: TextStyle(
                      color: Colors.orangeAccent,
                    )),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlayLists(),
                      fullscreenDialog: true,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildDrawer() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.95),
        backgroundBlendMode: BlendMode.darken,
      ),
      child: ListView(
        children: [
          UserAccountsDrawerHeader(
            margin: EdgeInsets.zero,
            decoration: BoxDecoration(
                image: DecorationImage(
                    colorFilter:
                        ColorFilter.mode(Colors.black87, BlendMode.darken),
                    image: AssetImage("images/quin.jpg"),
                    fit: BoxFit.cover)),
            accountName: Text(
              "Mugamba",
              style: TextStyle(color: Colors.orangeAccent),
            ),
            accountEmail: Text(
              "brunohectre@gmail.com",
              style: TextStyle(color: Colors.orangeAccent),
            ),
          ),
          Divider(
            color: Colors.orangeAccent,
            thickness: 0.46,
          ),
          ListTile(
              leading: Icon(Icons.settings, color: Colors.orangeAccent),
              title: Text(
                "Settings",
                style: TextStyle(color: Colors.orangeAccent),
              ),
              onTap: () {
                // Navigator.pop(context);
                drawerkey.currentState.closeDrawer();
              }),
          Divider(
            color: Colors.orangeAccent,
            thickness: 0.46,
          ),
          ListTile(
            leading:
                Icon(Icons.help_center_rounded, color: Colors.orangeAccent),
            title: Text(
              "Contact Support",
              style: TextStyle(color: Colors.orangeAccent),
            ),
          ),
          Divider(
            color: Colors.orangeAccent,
            thickness: 0.46,
          ),
          ListTile(
            leading: Icon(Icons.feedback_rounded, color: Colors.orangeAccent),
            title: Text(
              "FeedBack",
              style: TextStyle(color: Colors.orangeAccent),
            ),
          ),
        ],
      ),
    );
  }
}
