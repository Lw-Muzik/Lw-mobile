import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class Room extends StatefulWidget {
  final art;
  const Room({Key key,this.art}) : super(key: key);
  @override
  _Room createState( ) => _Room();
}

class _Room extends State<Room>{
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          // image: AssetImage("images/water.jpeg"),
          colorFilter: ColorFilter.mode(Colors.black87, BlendMode.darken),
          fit: BoxFit.cover,
          image: FileImage(File(widget.art)),
        )
      ),
      child: Center(
        child: Text("Room Effects",style: TextStyle(
        color: Colors.orangeAccent)),)
    );
  }
}