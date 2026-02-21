import '../exports/exports.dart';
import '/controllers/AppController.dart';
import '/widgets/Body.dart';
import 'graphic_eq_view.dart';
import 'parametric_eq_view.dart';
import 'space_view.dart';

// const Color _kAccent = Color(0xFFD4A825);

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
          actions: [
            // Global EQ toggle icon button
            // IconButton(
            //   icon: Icon(
            //     Icons.power_settings_new,
            //     color: appController.graphicEqEnabled
            //         ? _kAccent
            //         : Colors.white38,
            //   ),
            //   tooltip: appController.graphicEqEnabled
            //       ? "EQ is ON"
            //       : "EQ is OFF",
            //   onPressed: () {
            //     final newValue = !appController.graphicEqEnabled;
            //     appController.graphicEqEnabled = newValue;
            //     Channel.enableEq(newValue);
            //     Channel.enableDSPEngine(newValue);
            //     appController.enableDSP = newValue;
            //   },
            // ),
            const SizedBox(width: 4),
          ],
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
        borderRadius: BorderRadius.circular(24),
        color: accent.withValues(alpha: 0.15),
        border: Border.all(color: accent.withValues(alpha: 0.03), width: 1),
      ),
      labelColor: accent,
      unselectedLabelColor: Theme.of(
        context,
      ).colorScheme.onSurface.withValues(alpha: 0.6),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      tabs: const [
        Tab(icon: Icon(Icons.equalizer, size: 35)),
        Tab(icon: Icon(Icons.show_chart, size: 35)),
        Tab(icon: Icon(Icons.surround_sound, size: 35)),
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
