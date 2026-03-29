import 'dart:io';
import 'package:eq_app/controllers/drawer_controller.dart';

import '/exports/exports.dart';

import 'albums.dart';
import 'folders.dart';
import 'genres.dart';
import 'playlist.dart';
import 'search_page.dart';
import 'songs.dart';
import 'artists.dart';
import 'cloud/cloud_view.dart';
import 'cloud/discover_view.dart';
import 'equalizer.dart';
import 'Settings.dart';
import '/widgets/Body.dart';
import '/widgets/BottomPlayer.dart';
import '../Helpers/Channel.dart';
import '../controllers/AppController.dart';
import '../onboarding/coach_marks.dart';
import '../onboarding/home_guide.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with TickerProviderStateMixin {
  late final TabController _tabController;

  // Cache commonly used values
  late final AppController _appController;
  bool _isAndroid = false;

  // Tabs differ per platform — Folders and Playlists are Android-only
  late final List<_TabDef> _tabDefs;
  late final List<Widget> _tabViews;

  bool _initialized = false;

  // Coach marks — GlobalKeys for walkthrough targets
  final _searchKey = GlobalKey();
  final _tabBarKey = GlobalKey();
  final _menuKey = GlobalKey();
  final _coachController = CoachMarkController('home');

  @override
  void initState() {
    super.initState();
    _isAndroid = Platform.isAndroid;

    if (_isAndroid) {
      _tabDefs = const [
        _TabDef(Icons.folder_rounded, 'Folders'),
        _TabDef(Icons.queue_music_rounded, 'Playlists'),
        _TabDef(Icons.person_rounded, 'Artists'),
        _TabDef(Icons.album_rounded, 'Albums'),
        _TabDef(Icons.category_rounded, 'Genres'),
        _TabDef(Icons.music_note_rounded, 'Songs'),
        _TabDef(Icons.explore_rounded, 'Discover'),
        _TabDef(Icons.cloud_rounded, 'Cloud'),
      ];
      _tabViews = const [
        Folders(),
        PlayListView(),
        Artists(),
        Albums(),
        Genres(),
        AllSongs(),
        DiscoverView(),
        CloudView(),
      ];
    } else {
      // iOS: Discover first, no Folders/Playlists (unsupported)
      _tabDefs = const [
        _TabDef(Icons.explore_rounded, 'Discover'),
        _TabDef(Icons.cloud_rounded, 'Cloud'),
        _TabDef(Icons.person_rounded, 'Artists'),
        _TabDef(Icons.album_rounded, 'Albums'),
        _TabDef(Icons.category_rounded, 'Genres'),
        _TabDef(Icons.music_note_rounded, 'Songs'),
      ];
      _tabViews = const [
        DiscoverView(),
        CloudView(),
        Artists(),
        Albums(),
        Genres(),
        AllSongs(),
      ];
    }

    _tabController = TabController(length: _tabDefs.length, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appController = Provider.of<AppController>(context, listen: false);
    if (!_initialized) {
      _initialized = true;
      _initializeApp();
    }
  }

  Future<void> _initializeApp() async {
    if (_isAndroid) {
      await _loadAndroidSettings();
    }
  }

  Future<void> _tryShowCoachMarks() async {
    final shown = await _coachController.hasBeenShown();
    if (shown || !mounted) return;

    // Wait for layout to fully settle (tabs need ScrollPosition ready)
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    final discoverTabIndex =
        _tabDefs.indexWhere((t) => t.label == 'Discover');
    final songsTabIndex =
        _tabDefs.indexWhere((t) => t.label == 'Songs');

    void safeAnimateTab(int index) {
      if (!mounted) return;
      // Use index setter instead of animateTo — avoids crash when
      // TabBar's ScrollPosition hasn't attached a viewport yet
      _tabController.index = index;
    }

    _coachController.start(context, [
      CoachStep(
        targetKey: _tabBarKey,
        title: 'Your Music Tabs',
        description:
            'Swipe or tap tabs to browse your library — Discover, Artists, Albums, and more.',
        icon: Icons.tab_rounded,
        tooltipPosition: TooltipPosition.below,
      ),
      if (discoverTabIndex >= 0)
        CoachStep(
          targetKey: _tabBarKey,
          title: 'Discover New Music',
          description:
              'Tap the Discover tab to explore trending charts, popular songs, and artists.',
          icon: Icons.explore_rounded,
          tooltipPosition: TooltipPosition.below,
          onShow: () => safeAnimateTab(discoverTabIndex),
        ),
      if (songsTabIndex >= 0)
        CoachStep(
          targetKey: _tabBarKey,
          title: 'Your Songs',
          description:
              'Tap any song to play it. A mini player appears at the bottom.',
          icon: Icons.music_note_rounded,
          tooltipPosition: TooltipPosition.below,
          onShow: () => safeAnimateTab(songsTabIndex),
        ),
      CoachStep(
        targetKey: _searchKey,
        title: 'Search',
        description: 'Tap here to search across your entire music library.',
        icon: Icons.search_rounded,
        tooltipPosition: TooltipPosition.below,
      ),
      CoachStep(
        targetKey: _menuKey,
        title: 'Settings & EQ',
        description:
            'Open the menu for Settings, Equalizer, Visualizer, and more.',
        icon: Icons.menu_rounded,
        tooltipPosition: TooltipPosition.below,
      ),
    ]);
  }

  Future<void> _loadAndroidSettings() async {
    if (!mounted) return;
    // EQ and MBC are managed by the C++ DSP pipeline — initialized
    // automatically when the AudioProcessor starts in ExoPlayer.
    // Apply saved EQ state from AppController.
    Channel.enableEq(_appController.graphicEqEnabled);
    Channel.setPreamp(_appController.preampGain);
    Channel.setGraphicAllBands(_appController.graphicBandGains);
    Channel.enableMbc(_appController.mbcEnabled);

    // One-time battery optimization prompt
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('batteryOptPrompted') ?? false)) {
      final isDisabled = await Channel.isBatteryOptimizationDisabled();
      if (!isDisabled && mounted) {
        prefs.setBool('batteryOptPrompted', true);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Keep Music Playing"),
            content: const Text(
              "Android may stop Hype in the background to save battery.\n\n"
              "To enjoy uninterrupted music, allow unrestricted battery usage.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Later"),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Channel.requestDisableBatteryOptimization();
                },
                child: const Text("Allow"),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _coachController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _handleSearch() {
    showSearch<SongModel>(context: context, delegate: SearchPage());
  }

  @override
  Widget build(BuildContext context) {
    return HomeGuide(
      onComplete: _tryShowCoachMarks,
      child: Body(
        child: Consumer<AppController>(
          builder: (context, controller, _) {
            if (controller.isEqMode) {
              return Scaffold(
                backgroundColor: controller.isFancy
                    ? Colors.transparent
                    : Theme.of(context).scaffoldBackgroundColor,
                body: NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) => [
                    _buildEqModeSliverAppBar(controller),
                  ],
                  body: const Equalizer(),
                ),
              );
            }

            return Scaffold(
              backgroundColor: controller.isFancy
                  ? Colors.transparent
                  : Theme.of(context).scaffoldBackgroundColor,
              body: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  _buildSliverAppBar(controller, innerBoxIsScrolled),
                ],
                body: TabBarView(controller: _tabController, children: _tabViews),
              ),
              bottomNavigationBar: controller.handler.player.playing
                  ? BottomPlayer(controller: controller)
                  : null,
            );
          },
        ),
      ),
    );
  }

  Widget _buildEqModeSliverAppBar(AppController controller) {
    return SliverAppBar(
      floating: true,
      snap: true,
      pinned: false,
      forceMaterialTransparency: controller.isFancy,
      surfaceTintColor: Colors.transparent,
      expandedHeight: 80,
      toolbarHeight: 64,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 10),
        title: Row(
          children: [
            IconButton(
              key: _menuKey,
              icon: const Icon(Icons.menu_rounded),
              onPressed: () {
                context.read<DrawerProvider>().toggleDrawer();
              },
            ),
            const SizedBox(width: 4),
            const Expanded(
              child: Text(
                'Hype EQ',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_rounded, size: 22),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const Settings()),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        background: Container(color: Colors.transparent),
      ),
    );
  }

  Widget _buildSliverAppBar(AppController controller, bool innerBoxIsScrolled) {
    return SliverAppBar(
      floating: true,
      snap: true,
      pinned: false,
      forceMaterialTransparency: controller.isFancy,
      surfaceTintColor: Colors.transparent,
      // leading: Icon(Icons.menu),
      expandedHeight: 120,
      toolbarHeight: 64,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 52),
        title: Row(
          children: [
            IconButton(
              key: _menuKey,
              icon: const Icon(Icons.menu_rounded),
              onPressed: () {
                context.read<DrawerProvider>().toggleDrawer();
              },
            ),
            const SizedBox(width: 4),
            const Text(
              'Hype Muzik',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        background: Container(color: Colors.transparent),
      ),
      actions: [
        _buildActionButton(
          key: _searchKey,
          icon: Icons.search_rounded,
          onPressed: _handleSearch,
        ),
        // _buildActionButton(
        //   icon: Icons.tune_rounded,
        //   onPressed: () => Routes.routeTo(const Equalizer(), context),
        // ),
        // _buildActionButton(
        //   icon: Icons.settings_rounded,
        //   onPressed: () => Routes.routeTo(const Settings(), context),
        // ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: _buildTabBar(),
      ),
    );
  }

  Widget _buildActionButton({
    Key? key,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        key: key,
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        style: IconButton.styleFrom(
          foregroundColor: Colors.white.withValues(alpha: 0.85),
          padding: const EdgeInsets.all(10),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      alignment: Alignment.centerLeft,
      child: TabBar(
        key: _tabBarKey,
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        indicatorSize: TabBarIndicatorSize.label,
        dividerHeight: 0,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white.withValues(alpha: 0.12),
        ),
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.2,
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withValues(alpha: 0.45),
        splashBorderRadius: BorderRadius.circular(20),
        tabs: _tabDefs.map((def) {
          return Tab(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(def.icon, size: 16),
                  const SizedBox(width: 6),
                  Text(def.label),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TabDef {
  final IconData icon;
  final String label;
  const _TabDef(this.icon, this.label);
}
