import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class Tune extends StatefulWidget {
  final art;
  const Tune({Key key,this.art}) : super(key: key);
  _Tune createState() => _Tune();
}
class _Tune extends State<Tune>{
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage("images/water.jpeg"),
          colorFilter: ColorFilter.mode(Colors.black87, BlendMode.darken),
          fit: BoxFit.cover
          // image: FileImage(File(widget.art))
        )
      ),
      child: Center(child: Text("Tunning",style: TextStyle(
        color: Colors.orangeAccent)),),
    );
  }
}