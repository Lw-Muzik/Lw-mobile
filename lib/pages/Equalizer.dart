import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/controllers/AppController.dart';
import '/widgets/Body.dart';
import 'GraphicEqView.dart';
import 'ParametricEqView.dart';
import 'SpaceView.dart';

class Equalizer extends StatefulWidget {
  const Equalizer({super.key});

  @override
  State<Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<Equalizer> with TickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
          bottom: _buildTabBar(context),
        ),
        body: _buildTabBarView(),
      ),
    );
  }

  PreferredSizeWidget _buildTabBar(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return TabBar(
      controller: _tabController,
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: accent.withValues(alpha: 0.15),
      ),
      labelColor: accent,
      unselectedLabelColor: Theme.of(
        context,
      ).colorScheme.onSurface.withValues(alpha: 0.6),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      tabs: const [
        Tab(icon: Icon(Icons.equalizer, size: 20), text: "Graphic"),
        Tab(icon: Icon(Icons.show_chart, size: 20), text: "Parametric"),
        Tab(icon: Icon(Icons.surround_sound, size: 20), text: "Space"),
      ],
    );
  }

  Widget _buildTabBarView() {
    return SafeArea(
      child: TabBarView(
        controller: _tabController,
        children: const [GraphicEqView(), ParametricEqView(), SpaceView()],
      ),
    );
  }
}
