import 'package:flutter/material.dart';
import 'package:flutter_audio_query/flutter_audio_query.dart';

class PlayLists extends StatefulWidget {
  @override
  _PlayListsState createState() => _PlayListsState();
}

class _PlayListsState extends State<PlayLists> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder(
          future: FlutterAudioQuery().getPlaylists(),
          // ignore: missing_return
          builder: (context,AsyncSnapshot snapshot){
            List<PlaylistInfo> jams = snapshot.data;
            if(snapshot.hasData)
             if(jams.length == null)
                return Center(
                  child: Container(
                    child: Text("No Albums found"),
                  ),
                );
                else
              return LoadPlaylist(albums:jams);
            else
              return Padding(
                 padding: const EdgeInsets.only(top:240),
                 child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      Padding(
                        padding: const EdgeInsets.all(15),
                        child: Text("Loading playlists",
                        style:TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ) ,
                        ),
                      ),
                    ],
                  ),
              ),
               );
          })
      ),
    );
  }
}
class LoadPlaylist extends StatefulWidget {
  final List<PlaylistInfo> albums;
  const LoadPlaylist({Key key,this.albums}):super(key: key);
  @override
  _LoadPlaylistState createState() => _LoadPlaylistState();
}

class _LoadPlaylistState extends State<LoadPlaylist> {
  @override
  Widget build(BuildContext context) {
    return Container(
      child: ListView.separated(itemBuilder: (context,index){
        return ListTile(
          title:Text(widget.albums[index].name,style: TextStyle(color: Colors.deepOrange),),
          subtitle:Text(widget.albums[index].creationDate,style: TextStyle(color: Colors.deepOrange),),
        );
      }, separatorBuilder:(context,data)=> Divider(), itemCount: widget.albums.length),
    );
  }
}