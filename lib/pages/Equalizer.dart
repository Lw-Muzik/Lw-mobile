import 'package:eq_app/Helpers/Channel.dart';
import 'package:eq_app/controllers/AppController.dart';
import 'package:eq_app/pages/AudioFx.dart';
import 'package:eq_app/pages/Room.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    if (mounted) {
      // Channel.setSessionId(0);
    }

    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController!.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int?>(
        stream: context
            .read<AppController>()
            .audioPlayer
            .androidAudioSessionIdStream,
        builder: (context, snapshot) {
          int? x = snapshot.data;
          if (snapshot.hasData && x != null) {
            Channel.setSessionId(x);
          }
          return Scaffold(
            appBar: AppBar(
              title: const Text("Sound Effects"),
              bottom: TabBar(
                // isScrollable: true,
                controller: _tabController,
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: "Equalizer"),
                  Tab(text: "Audio FX"),
                  Tab(text: "Room Effects"),
                ],
              ),
            ),
            body: Center(
              child: TabBarView(
                // physics: const NeverScrollableScrollPhysics(),
                controller: _tabController,
                children: const [EqView(), AudioFx(), RoomEffects()],
              ),
            ),
          );
        });
  }
}
