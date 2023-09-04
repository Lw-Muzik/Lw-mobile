import 'dart:developer';

import 'package:eq_app/pages/Room.dart';
import 'package:eq_app/widgets/CircularKnob.dart';
import 'package:flutter/material.dart';
import 'package:sleek_circular_slider/sleek_circular_slider.dart';

import '../Helpers/Channel.dart';
import 'EqView.dart';

class Equalizer extends StatefulWidget {
  const Equalizer({super.key});

  @override
  State<Equalizer> createState() => _EqualizerState();
}

List<int> bandLevel = [-10, 10];
String? preset;

class _EqualizerState extends State<Equalizer> with TickerProviderStateMixin {
  bool eq = false;
  TabController? _tabController;
  List<double> bandValues = [0, 0, 0, 0, 0];
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController!.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Sound Effects"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Equalizer"),
            Tab(text: "Room Effects"),
            Tab(text: "Controls"),
          ],
        ),
      ),
      body: Center(
        child: TabBarView(
          // physics: const NeverScrollableScrollPhysics(),
          controller: _tabController,
          children: const [EqView(), RoomEffects(), SizedBox()],
        ),
      ),
    );
  }
}
