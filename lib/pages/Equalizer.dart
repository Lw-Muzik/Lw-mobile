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
import '../themes/ember.dart';

/// The app's one accent, not a fifth colour invented for this screen.
///
/// This page used to carry four: a red tab indicator from the theme, a muted
/// gold for boost, a cyan for cut, and white knobs. None of them was the logo's.
const Color _kAccent = Ember.accent;

/// A cut is the same colour as a boost, dimmed — not a second hue.
///
/// Cyan against gold read as two unrelated controls rather than one control
/// pushed either side of flat.
const Color _kCut = Color(0xFFB08A2E);

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
        // The body is a column of Expanded flexes, so shrinking it does not
        // scroll — it crushes. When the preset sheet's search field raises the
        // keyboard, the curve collapses to a line and the faders to a row of
        // bare caps. Nothing on this page needs to dodge the keyboard, so it
        // keeps its height and the sheet floats over it.
        resizeToAvoidBottomInset: false,
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
        borderRadius: BorderRadius.circular(14),
        color: accent.withValues(alpha: 0.16),
        border: Border.all(color: accent.withValues(alpha: 0.34)),
      ),
      labelColor: accent,
      unselectedLabelColor: Theme.of(
        context,
      ).colorScheme.onSurface.withValues(alpha: 0.6),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      tabs: [
        const Tab(icon: Icon(Icons.equalizer_rounded, size: 22)),
        const Tab(icon: Icon(Icons.tune_rounded, size: 22)),
        if (!_isEqMode) ...[
          const Tab(icon: Icon(Icons.show_chart_rounded, size: 22)),
          const Tab(icon: Icon(Icons.surround_sound_rounded, size: 22)),
          const Tab(icon: Icon(Icons.headphones_rounded, size: 22)),
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
