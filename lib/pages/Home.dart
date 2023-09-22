import 'dart:convert';
import 'dart:developer';

import 'package:eq_app/pages/Playlist.dart';
import 'package:flutter/cupertino.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
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
    // showChangeLog();
    fetchSongs();
    restoreDefaults();
    // checkAndRequestPermissions();
    checkPermission().then((value) {
      for (var element in value) {
        if (element.isGranted) {
          fetchSongs();
        }
      }
    });
  }

  // void showChangeLog() {
  //   showCupertinoModalPopup(
  //       context: context,
  //       builder: (context) {
  //         return Dialog();
  //       });
  // }

  void fetchSongs() async {
    if (mounted) {
      setState(() {});
      context.read<AppController>().songs =
          await context.read<AppController>().audioQuery.querySongs(
                orderType: OrderType.ASC_OR_SMALLER,
                uriType: UriType.EXTERNAL,
                ignoreCase: true,
              );
      // ignore: use_build_context_synchronously
      context.read<AppController>().playlist =
          await OnAudioQuery.platform.queryPlaylists();
    }
  }

  void restoreDefaults() {
    if (mounted) {
      // setState(() {
      //   eq = Provider.of<AppController>(context, listen: false).enableDSP;
      // });
      Channel.enableEq(
          Provider.of<AppController>(context, listen: false).enableDSP);
      setState(() {});
      Channel.enableDSPEngine(
          Provider.of<AppController>(context, listen: false).enableDSP);
      setState(() {});
    }
  }

  Future<List<PermissionStatus>> checkPermission() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.audio,
      Permission.storage,
      Permission.manageExternalStorage,
    ].request();
    return statuses.values.toList();
  }

  bool pPlay = false;
  @override
  Widget build(BuildContext context) {
    Channel.setSessionId(0);

    // var controller = Provider.of<AppController>(context, listen: true);
    return Consumer<AppController>(builder: (context, controller, s) {
      return StreamBuilder(
          stream: controller.audioHandler.playingStream,
          builder: (context, service) {
            return Body(
              child: Scaffold(
                backgroundColor: controller.isFancy
                    ? Colors.transparent
                    : Theme.of(context).scaffoldBackgroundColor,
                appBar: AppBar(
                  forceMaterialTransparency: controller.isFancy,
                  title: const Text("Hype Muziki"),
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
                      child: Routes.animateTo(
                        closedWidget: const Icon(Icons.equalizer),
                        openWidget: const Equalizer(),
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
                body: StreamBuilder(
                    stream: Stream.fromFuture(checkPermission()),
                    builder: (context, snapshot) {
                      var permission = snapshot.data;
                      return snapshot.hasData
                          ? permission![0].isGranted ||
                                  permission[1].isGranted ||
                                  permission[0].isGranted
                              ? Stack(
                                  children: [
                                    GestureDetector(
                                      onScaleUpdate: (details) {
                                        log(details.scale.toString());
                                      },
                                      child: TabBarView(
                                        controller: _tabController,
                                        children: const [
                                          Folders(),
                                          PlayListView(),
                                          Artists(),
                                          Albums(),
                                          Genres(),
                                          AllSongs(),
                                        ],
                                      ),
                                    ),
                                    // if (controller.audioPlayer.playing)
                                    //   Positioned(
                                    //     bottom: 0,
                                    //     right: 3,
                                    //     left: 3,
                                    //     child: BottomPlayer(
                                    //       controller: controller,
                                    //     ),
                                    //   ),
                                  ],
                                )
                              : Center(
                                  child: OutlinedButton(
                                    onPressed: () {
                                      checkPermission().then((value) {
                                        setState(() {});
                                      });
                                    },
                                    child: const Text("Request permission"),
                                  ),
                                )
                          : const Center(
                              child: CircularProgressIndicator.adaptive(),
                            );
                    }),
                bottomNavigationBar: service.data ?? false
                    ? BottomPlayer(
                        controller: controller,
                      )
                    : null,
              ),
            );
          });
    });
  }
}
