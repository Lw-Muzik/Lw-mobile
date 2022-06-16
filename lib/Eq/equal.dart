import 'package:app/Eq/eq.dart';
import 'package:app/Eq/room.dart';
import 'package:app/Eq/tune.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class Equal extends StatefulWidget {
  Equal({Key key}) : super(key: key);

  @override
  _EqualState createState() => _EqualState();
}

class _EqualState extends State<Equal> {
  @override
  Widget build(BuildContext context) {
     return OrientationBuilder(
      builder: (context,Orientation orientation){
      return orientation == Orientation.portrait ? PortEq() : LandEq();
    });
  }
}

class PortEq extends StatefulWidget {
  PortEq({Key key}) : super(key: key);

  @override
  _PortEqState createState() => _PortEqState();
}

class _PortEqState extends State<PortEq> {
  Widget _currentPage;
  List pages = [];
  int index = 0;
  void initState(){
    super.initState();
    pages..add(Eq())..add(Tune())..add(Room());
  _currentPage = pages[index];
  }

  void _nextPage(int value){
    setState(() {
       index = value;
    _currentPage = pages[value];
    });
   
    
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: _currentPage),
      floatingActionButton: FloatingActionButton.extended(
        splashColor: Colors.orange[200],
        backgroundColor: Colors.black,
        
        onPressed: (){
          Navigator.pop(context);
        },
        icon: Icon(Icons.arrow_back_ios_rounded,color: Colors.orangeAccent,),
       label: Text("Back",style: TextStyle(color: Colors.orangeAccent),)),
       bottomNavigationBar: BottomNavigationBar(
        //  selectedIconTheme: IconThemeData.fallback(),
        selectedItemColor: Colors.orangeAccent,
         backgroundColor: Colors.black87,
         unselectedItemColor: Colors.white54,
         elevation: 20.0,

         currentIndex: index,
          onTap: (index){
           _nextPage(index);
         },
         items: [
         BottomNavigationBarItem(icon: Icon(Icons.bar_chart_sharp),
         
         label: "Equalizer",
         ),
          BottomNavigationBarItem(icon: Icon(Icons.tune_rounded),
         label: "Audio Tunning",
         ),
          BottomNavigationBarItem(icon: Icon(Icons.surround_sound),
         label: "Room Effects",
         )
       ]),
    );
  }
}

class LandEq extends StatefulWidget {
  LandEq({Key key}) : super(key: key);

  @override
  _LandEqState createState() => _LandEqState();
}

class _LandEqState extends State<LandEq> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(

      )),
    );
  }
}