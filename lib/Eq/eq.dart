import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';

class Eq extends StatefulWidget {
  final art;
  const Eq({Key key,this.art}) : super(key: key);
  _Eq createState() => _Eq();
  
  }

  class _Eq extends State<Eq>{
    double _vl1 = 10,_vl2 = 12, _vl3 = 11, _vl4 = 15;
    // bool _expand = false;
    bool isOn = false;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          // image: AssetImage("images/water.jpeg"),
          colorFilter: ColorFilter.mode(Colors.black87, BlendMode.darken),
          fit: BoxFit.cover,
          image: FileImage(File(widget.art))
        )
      ),
      child: ListView(
        children: <Widget>[
          SwitchListTile(
            tileColor: Colors.orangeAccent,
            subtitle: Text("This feature allows the user to access the system AudioFx"),
            title: Text("Enable Built-in Audio Fx"),
            value: isOn, 
          onChanged: (value){
           setState(() {
             value = ! value;
           });
          }),
          Divider(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          mainAxisSize: MainAxisSize.max,
          children: [
                SfSlider.vertical(
                value: _vl1,
                 min: 0.0,
                max: 100.0,
                interval: 20,
                showTicks: true,
                showLabels: true,
                enableTooltip: true,
                minorTicksPerInterval: 1,
               onChanged: (value){
                 setState(() {
                   _vl1 = value;
                 });
               },
              ),

SfSlider.vertical(
                value: _vl2,
                 min: 0.0,
                max: 100.0,
                interval: 30,
                showTicks: true,
                showLabels: true,
                enableTooltip: true,
                minorTicksPerInterval: 1,
               onChanged: (value){
                 setState(() {
                   _vl2 = value;
                 });
               },
              ),
SfSlider.vertical(
                value: _vl3,
                 min: 0.0,
                max: 100.0,
                interval: 20,
                showTicks: true,
                showLabels: true,
                enableTooltip: true,
                minorTicksPerInterval: 1,
               onChanged: (value){
                 setState(() {
                   _vl3 = value;
                 });
               },
              ),

              SfSlider.vertical(
                value: _vl4,
                 min: 0.0,
                max: 100.0,
                interval: 20,
                showTicks: true,
                showLabels: true,
                enableTooltip: true,
                minorTicksPerInterval: 1,
               onChanged: (value){
                 setState(() {
                   _vl4 = value;
                 });
               },
              ),

              // SfSlider.vertical(
              //   value: _vl1,
              //    min: 0.0,
              //   max: 100.0,
              //   interval: 20,
              //   showTicks: true,
              //   showLabels: true,
              //   enableTooltip: true,
              //   minorTicksPerInterval: 1,
              //  onChanged: (value){
              //    setState(() {
              //      _vl1 = value;
              //    });
              //  },
              

          ],
        ),
  
        ],
      ),
    );
  }
}