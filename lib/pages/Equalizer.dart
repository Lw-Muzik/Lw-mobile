import '../exports/exports.dart';
import '/controllers/app_controller.dart';
import '/Helpers/Channel.dart';
import '/widgets/Body.dart';
import '../controllers/drawer_controller.dart';
import '../onboarding/coach_marks.dart';
import 'Settings.dart';
import 'graphic_eq_view.dart';
import 'tone_view.dart';
import 'parametric_eq_view.dart';
import 'space_view.dart';
import 'speaker_eq_view.dart';

const Color _kAccent = Color(0xFFD4A825);

class Equalizer extends StatefulWidget {
  const Equalizer({super.key});

  @override
  State<Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<Equalizer> with TickerProviderStateMixin {
  late final TabController _tabController;
  final _coachController = CoachMarkController('equalizer');
  final _tabBarKey = GlobalKey();
  final _contentKey = GlobalKey();

  bool _isEqMode = false;

  @override
  void initState() {
    super.initState();
    _isEqMode = context.read<AppController>().isEqMode;
    _tabController = TabController(length: _isEqMode ? 2 : 5, vsync: this);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      _coachController.hasBeenShown().then((shown) {
        if (!shown && mounted) {
          _coachController.start(context, [
            CoachStep(
              targetKey: _tabBarKey,
              title: 'Effect Tabs',
              description:
                  'Switch between Graphic EQ, Tone controls, Parametric EQ, and Spatial effects.',
              icon: Icons.tab,
              tooltipPosition: TooltipPosition.below,
            ),
            CoachStep(
              targetKey: _contentKey,
              title: 'Shape Your Sound',
              description:
                  'Drag sliders to shape your sound. Tap presets for quick EQ curves.',
              icon: Icons.equalizer,
              tooltipPosition: TooltipPosition.above,
            ),
          ]);
        }
      });
    });
  }

  @override
  void dispose() {
    _coachController.dispose();
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
          leading: _isEqMode
              ? IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () {
                    context.read<DrawerProvider>().toggleDrawer();
                  },
                )
              : null,
          title: Text(_isEqMode ? "Hype EQ" : "Sound Effects"),
          actions: [
            _EqPowerAction(
              enabled: appController.graphicEqEnabled,
              onToggle: () {
                final newValue = !appController.graphicEqEnabled;
                appController.graphicEqEnabled = newValue;
                Channel.enableEq(newValue);
              },
            ),
            if (_isEqMode)
              IconButton(
                icon: const Icon(Icons.settings_rounded, size: 22),
                onPressed: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const Settings()));
                },
              ),
            const SizedBox(width: 12),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(kTextTabBarHeight),
            child: KeyedSubtree(key: _tabBarKey, child: _buildTabBar(context)),
          ),
        ),
        body: KeyedSubtree(key: _contentKey, child: _buildTabBarView()),
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
      tabs: [
        const Tab(icon: Icon(Icons.equalizer, size: 35)),
        const Tab(icon: Icon(Icons.tune, size: 35)),
        if (!_isEqMode) ...[
          const Tab(icon: Icon(Icons.show_chart, size: 35)),
          const Tab(icon: Icon(Icons.surround_sound, size: 35)),
          const Tab(icon: Icon(Icons.headphones, size: 35)),
        ],
      ],
    );
  }

  Widget _buildTabBarView() {
    return SafeArea(
      child: TabBarView(
        physics: const NeverScrollableScrollPhysics(),
        controller: _tabController,
        children: [
          const GraphicEqView(),
          const ToneView(),
          if (!_isEqMode) ...[
            const ParametricEqView(),
            const SpaceView(),
            const SpeakerEqView(),
          ],
        ],
      ),
    );
  }
}

class _EqPowerAction extends StatelessWidget {
  final bool enabled;
  final VoidCallback onToggle;

  const _EqPowerAction({required this.enabled, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled
                  ? _kAccent.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.06),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: _kAccent.withValues(alpha: 0.4),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : [],
              border: Border.all(
                color: enabled ? _kAccent : Colors.white24,
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.power_settings_new,
              size: 16,
              color: enabled ? _kAccent : Colors.white38,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            enabled ? "ON" : "OFF",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: enabled ? _kAccent : Colors.white38,
            ),
          ),
        ],
      ),
    );
  }
}
