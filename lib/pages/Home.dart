import 'dart:convert';
import 'dart:io';
import 'package:eq_app/controllers/drawer_controller.dart';

import '/exports/exports.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/Routes/routes.dart';
import '/pages/Albums.dart';
import '/pages/Equalizer.dart';
import '/pages/Folders.dart';
import '/pages/Genres.dart';
import '/pages/Playlist.dart';
import '/pages/SearchPage.dart';
import '/pages/Settings.dart';
import '/pages/Songs.dart';
import '/pages/Artists.dart';
import 'cloud/cloud_view.dart';
import '/widgets/Body.dart';
import '/widgets/BottomPlayer.dart';
import '../Helpers/Channel.dart';
import '../controllers/AppController.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with TickerProviderStateMixin {
  late final TabController _tabController;
  // ignore: constant_identifier_names
  static const int TAB_COUNT = 7;

  // Cache commonly used values
  late final AppController _appController;
  bool _isAndroid = false;

  static const List<_TabDef> _tabDefs = [
    _TabDef(Icons.folder_rounded, 'Folders'),
    _TabDef(Icons.queue_music_rounded, 'Playlists'),
    _TabDef(Icons.person_rounded, 'Artists'),
    _TabDef(Icons.album_rounded, 'Albums'),
    _TabDef(Icons.category_rounded, 'Genres'),
    _TabDef(Icons.music_note_rounded, 'Songs'),
    _TabDef(Icons.cloud_rounded, 'Cloud'),
  ];

  static const List<Widget> _tabViews = [
    Folders(),
    PlayListView(),
    Artists(),
    Albums(),
    Genres(),
    AllSongs(),
    CloudView(),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: TAB_COUNT, vsync: this);
    _isAndroid = Platform.isAndroid;

    // Initialize permissions and settings
    _initializeApp();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appController = Provider.of<AppController>(context, listen: false);
  }

  Future<void> _initializeApp() async {
    if (_isAndroid) {
      await _loadAndroidSettings();
    }
  }

  Future<void> _loadAndroidSettings() async {
    final pref = await SharedPreferences.getInstance();

    if (!mounted) return;

    // Load DSP settings
    final enableDSP = pref.getBool("enableDSP") ?? false;
    _appController.enableDSP = enableDSP;

    // Apply DSP settings in batch
    // await Future.wait<void>([
    Channel.enableEq(enableDSP);
    Channel.enableDSPEngine(enableDSP);
    // ]);

    // Load cached values
    _appController
      ..dspOutGain = pref.getDouble("powerGain") ?? 3.0
      ..dspPowerBass = pref.getDouble("powerBass") ?? 8.0
      ..dspXTreble = pref.getDouble("xTreble") ?? 3.3
      ..dspVolume = pref.getDouble("dspVolume") ?? -6.0
      ..dspXBass = pref.getDouble("xBass") ?? 11.0;

    // Load and apply speaker configuration
    final stored = pref.getString("dsp_speakers");
    if (stored != null) {
      final dsp = json.decode(stored);
      Channel.setDSPSpeakers(dsp['speakers'], dsp['levels']);
    }

    // Apply DSP settings
    // await Future.wait<void>([
    Channel.setDSPVolume(_appController.dspVolume);
    Channel.setDSPTreble(_appController.dspXTreble);
    Channel.setDSPPowerBass(_appController.dspPowerBass);
    Channel.setDSPXBass(_appController.dspXBass);
    // ]);
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
    return Body(
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
