// ignore_for_file: unnecessary_null_comparison

import 'dart:convert';
import 'dart:io';
import '/exports/exports.dart';
import 'package:permission_handler/permission_handler.dart';
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
import '/widgets/Body.dart';
import '/widgets/BottomPlayer.dart';
import '../Helpers/Channel.dart';
import '../controllers/AppController.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> with TickerProviderStateMixin {
  late final TabController _tabController;
  static const int TAB_COUNT = 6;

  // Cache commonly used values
  late final AppController _appController;
  bool _isAndroid = false;

  // Constant tab definitions to avoid rebuilds
  static const List<Tab> _tabs = [
    Tab(child: Text("Folders")),
    Tab(child: Text("Playlists")),
    Tab(child: Text("Artists")),
    Tab(child: Text("Albums")),
    Tab(child: Text("Genres")),
    Tab(child: Text("Songs")),
  ];

  static const List<Widget> _tabViews = [
    Folders(),
    PlayListView(),
    Artists(),
    Albums(),
    Genres(),
    AllSongs(),
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
    await _checkPermission();
    if (_isAndroid) {
      await _loadAndroidSettings();
    }
  }

  Future<void> _checkPermission() async {
    var permissionStatus = await Permission.storage.status;
    if (!permissionStatus.isGranted) {
      await Future.wait([
        Permission.storage.request(),
        Permission.audio.request(),
        Permission.accessMediaLocation.request(),
      ]);
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
    Channel.setOutGain(_appController.dspOutGain);
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
          appBar: _buildAppBar(controller),
          body: TabBarView(controller: _tabController, children: _tabViews),
          bottomNavigationBar: controller.handler.player.playing
              ? BottomPlayer(controller: controller)
              : null,
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AppController controller) {
    return AppBar(
      forceMaterialTransparency: controller.isFancy,
      title: const Text("Hype Muzik"),
      actions: [
        IconButton(
          onPressed: _handleSearch,
          icon: const Icon(Icons.search),
          padding: const EdgeInsets.only(right: 18.0),
        ),
        IconButton(
          onPressed: () => Routes.routeTo(const Settings(), context),
          icon: const Icon(Icons.settings),
          padding: const EdgeInsets.only(right: 18.0),
        ),
        IconButton(
          onPressed: () => Routes.routeTo(const Equalizer(), context),
          icon: const Icon(Icons.equalizer),
          padding: const EdgeInsets.only(right: 18.0),
        ),
      ],
      bottom: TabBar(
        isScrollable: true,
        controller: _tabController,
        tabs: _tabs,
      ),
    );
  }
}
