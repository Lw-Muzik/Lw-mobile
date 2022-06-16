// import 'package:flutter/material.dart';
// import 'package:flutter_audio_query/flutter_audio_query.dart';

// class Genres extends StatefulWidget {
//   @override
//   _GenresState createState() => _GenresState();
// }

// class _GenresState extends State<Genres> {
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: SafeArea(
//         child: FutureBuilder(
//           future: FlutterAudioQuery().getGenres(),
//           // ignore: missing_return
//           builder: (context,AsyncSnapshot snapshot){
//             List<GenreInfo> jams = snapshot.data;
//             if(snapshot.hasData)
//               return LoadGenres(albums:jams);
//             else
//               return Padding(
//                  padding: const EdgeInsets.only(top:240),
//                  child: Center(
//                   child: Column(
//                     children: [
//                       CircularProgressIndicator(),
//                       Padding(
//                         padding: const EdgeInsets.all(15),
//                         child: Text("Loading Genres",
//                         style:TextStyle(
//                           fontWeight: FontWeight.bold,
//                           fontSize: 17,
//                         ) ,
//                         ),
//                       ),
//                     ],
//                   ),
//               ),
//                );
//           })
//       ),
//     );
//   }
// }

// class LoadGenres extends StatefulWidget {
//   final List<GenreInfo> albums;
//   const LoadGenres({Key key,this.albums}):super(key: key);
//   @override
//   _LoadGenresState createState() => _LoadGenresState();
// }

// class _LoadGenresState extends State<LoadGenres> {
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       child: ListView.separated(itemBuilder: (context,index){
//         return ListTile(
//           title:Text(widget.albums[index].name,style: TextStyle(color: Colors.deepOrange),)
//         );
//       }, separatorBuilder:(context,data)=> Divider(), itemCount: widget.albums.length),
//     );
//   }
// }