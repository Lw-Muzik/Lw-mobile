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
import '/widgets/Body.dart';
import '/widgets/BottomPlayer.dart';
import '../Helpers/Channel.dart';
import '../controllers/AppController.dart';
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
        _TabDef(Icons.cloud_rounded, 'Cloud'),
      ];
      _tabViews = const [
        Folders(),
        PlayListView(),
        Artists(),
        Albums(),
        Genres(),
        AllSongs(),
        CloudView(),
      ];
    } else {
      // iOS: no Folders (no filesystem access), no Playlists (unsupported)
      _tabDefs = const [
        _TabDef(Icons.person_rounded, 'Artists'),
        _TabDef(Icons.album_rounded, 'Albums'),
        _TabDef(Icons.category_rounded, 'Genres'),
        _TabDef(Icons.music_note_rounded, 'Songs'),
        _TabDef(Icons.cloud_rounded, 'Cloud'),
      ];
      _tabViews = const [
        Artists(),
        Albums(),
        Genres(),
        AllSongs(),
        CloudView(),
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

  Future<void> _loadAndroidSettings() async {
    if (!mounted) return;
    // EQ and MBC are managed by the C++ DSP pipeline — initialized
    // automatically when the AudioProcessor starts in ExoPlayer.
    // Apply saved EQ state from AppController.
    Channel.enableEq(_appController.graphicEqEnabled);
    Channel.setPreamp(_appController.preampGain);
    Channel.setGraphicAllBands(_appController.graphicBandGains);
    Channel.enableMbc(_appController.mbcEnabled);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _handleSearch() {
    showSearch<SongModel>(context: context, delegate: SearchPage());
  }

  @override
  Widget build(BuildContext context) {
    return HomeGuide(
      child: Body(
        child: Consumer<AppController>(
          builder: (context, controller, _) => Scaffold(
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
          ),
        ),
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
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
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
