// ignore_for_file: unnecessary_null_comparison

import 'dart:convert';
import 'dart:io';
import 'dart:developer';

import 'package:eq_app/pages/Playlist.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/Routes/routes.dart';
import '/pages/Albums.dart';
import '/pages/Equalizer.dart';
import '/pages/Folders.dart';
import '/pages/Genres.dart';
import '/pages/SearchPage.dart';
import '/widgets/Body.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../Helpers/Channel.dart';
import '../controllers/AppController.dart';
import '../widgets/BottomPlayer.dart';
import 'Artists.dart';
// import 'Recents.dart';
import 'Settings.dart';
import 'Songs.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> with TickerProviderStateMixin {
  TabController? _tabController;

  // Indicate if application has permission to the library.
  GlobalKey keyButton = GlobalKey();
  @override
  void initState() {
    checkPermission();
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    if (Platform.isAndroid) {
      SharedPreferences.getInstance().then((pref) {
        setState(() {
          Provider.of<AppController>(context, listen: false).enableDSP =
              pref.getBool("enableDSP") ?? false;

          Channel.enableEq(pref.getBool("enableDSP") ?? false);

          Channel.enableDSPEngine(pref.getBool("enableDSP") ?? false);

          context.read<AppController>().dspOutGain =
              pref.getDouble("powerGain") ?? 3.0;
          context.read<AppController>().dspPowerBass =
              pref.getDouble("powerBass") ?? 8.0;
          context.read<AppController>().dspXTreble =
              pref.getDouble("xTreble") ?? 3.3;
          context.read<AppController>().dspVolume =
              pref.getDouble("dspVolume") ?? -6.0;
          context.read<AppController>().dspXBass =
              pref.getDouble("xBass") ?? 11.0;
        });
        String? stored = pref.getString("dsp_speakers");
        if (stored != null) {
          var dsp = json.decode(stored);
          // config the system to default
          Channel.setDSPSpeakers(dsp['speakers'], dsp['levels']);
        }
        Channel.setDSPVolume(pref.getDouble("dspVolume") ?? -6.0);
        Channel.setDSPTreble(pref.getDouble("xTreble") ?? 3.3);
        Channel.setDSPPowerBass(pref.getDouble("powerBass") ?? 8.0);
        Channel.setDSPXBass(pref.getDouble("xBass") ?? 11.0);
        Channel.setOutGain(pref.getDouble("powerGain") ?? 3.0);
      });
    }
  }

  void checkPermission() async {
    var permissionStatus = await Permission.storage.status;
    if (permissionStatus.isDenied ||
        permissionStatus.isPermanentlyDenied ||
        permissionStatus.isRestricted ||
        permissionStatus.isLimited) {
      await Permission.storage.request();
      await Permission.audio.request();
      await Permission.accessMediaLocation.request();
    }
  }

  void restoreDefaults() {
    if (mounted) {
      Channel.enableEq(
          Provider.of<AppController>(context, listen: false).enableDSP);
      setState(() {});
      Channel.enableDSPEngine(
          Provider.of<AppController>(context, listen: false).enableDSP);
      setState(() {});
    }
  }

  bool pPlay = false;
  @override
  Widget build(BuildContext context) {
    return Body(
      child: Consumer<AppController>(builder: (context, controller, c) {
        return Scaffold(
          backgroundColor: controller.isFancy
              ? Colors.transparent
              : Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            forceMaterialTransparency: controller.isFancy,
            title: const Text("Hype Muzik"),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 18.0),
                child: IconButton(
                  onPressed: () {
                    showSearch<SongModel>(
                        context: context, delegate: SearchPage());
                  },
                  icon: const Icon(Icons.search),
                ),
              ),
              Padding(
                key: keyButton,
                padding: const EdgeInsets.only(right: 18.0),
                child: IconButton(
                  onPressed: () {
                    Routes.routeTo(const Settings(), context);
                  },
                  icon: const Icon(Icons.settings),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 18.0),
                child: IconButton(
                  onPressed: () {
                    Routes.routeTo(const Equalizer(), context);
                  },
                  icon: const Icon(Icons.equalizer),
                ),
              )
            ],
            bottom: TabBar(
              isScrollable: true,
              controller: _tabController,
              tabs: const [
                Tab(
                  child: Text("Folders"),
                ),
                // Tab(
                //   child: Text("Recently Added"),
                // ),
                Tab(
                  child: Text("Playlists"),
                ),
                Tab(
                  child: Text("Artists"),
                ),
                Tab(
                  child: Text("Albums"),
                ),
                Tab(
                  child: Text("Genres"),
                ),
                Tab(
                  child: Text("Songs"),
                ),
              ],
            ),
          ),
          body: Stack(
            children: [
              TabBarView(
                controller: _tabController,
                children: const [
                  Folders(),
                  // Recents(),
                  PlayListView(),
                  Artists(),
                  Albums(),
                  Genres(),
                  AllSongs(),
                ],
              ),
            ],
          ),
          bottomNavigationBar: controller.handler.player.playing
              ? BottomPlayer(
                  controller: controller,
                )
              : null,
        );
      }),
    );
  }
}
