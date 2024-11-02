import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// custom files
import '/Helpers/Channel.dart';
import '/controllers/AppController.dart';
import '/pages/Compressor.dart';
import '/widgets/Body.dart';
import 'AudioFx.dart';
import 'EqView.dart';
import 'Room.dart';

class Equalizer extends StatefulWidget {
  const Equalizer({super.key});

  @override
  State<Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<Equalizer> with TickerProviderStateMixin {
  late final TabController _tabController;
  final List<double> bandValues = [0, 0, 0, 0, 0];
  static const List<int> bandLevel = [-10, 10];
  String? preset;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    // Setting up listener for android audio session ID.
    context
        .read<AppController>()
        .handler
        .player
        .androidAudioSessionIdStream
        .listen((event) {
      if (event != null) {
        Channel.setSessionId(event);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appController = context.watch<AppController>();
    return Body(
      child: Scaffold(
        backgroundColor: appController.isFancy
            ? Colors.transparent
            : Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          forceMaterialTransparency: appController.isFancy,
          title: const Text("Sound Effects"),
          bottom: _buildTabBar(),
        ),
        body: _buildTabBarView(),
      ),
    );
  }

  TabBar _buildTabBar() {
    return TabBar(
      isScrollable: true,
      controller: _tabController,
      dividerColor: Colors.transparent,
      tabs: const [
        Tab(text: "Equalizer"),
        Tab(text: "Audio FX"),
        Tab(text: "Compressor"),
        Tab(text: "Room Effects"),
      ],
    );
  }

  Widget _buildTabBarView() {
    return TabBarView(
      controller: _tabController,
      children: const [
        EqView(),
        AudioFx(),
        CompressorView(),
        RoomEffects(),
      ],
    );
  }
}
