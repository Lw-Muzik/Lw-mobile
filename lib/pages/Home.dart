import 'dart:developer';

import 'package:eq_app/pages/Albums.dart';
import 'package:eq_app/pages/Folders.dart';
import 'package:eq_app/pages/Genres.dart';
import 'package:eq_app/pages/SearchPage.dart';
import 'package:eq_app/widgets/Body.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../Helpers/Channel.dart';
import '../controllers/AppController.dart';
import '../widgets/BottomPlayer.dart';
import 'Artists.dart';
import 'Songs.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> with TickerProviderStateMixin {
  TabController? _tabController;
  // Indicate if application has permission to the library.
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    fetchSongs();
    checkAndRequestPermissions();
  }

  void fetchSongs() async {
    if (mounted) {
      setState(() {});
      context.read<AppController>().songs =
          await context.read<AppController>().audioQuery.querySongs(
                sortType: null,
                orderType: OrderType.ASC_OR_SMALLER,
                uriType: UriType.EXTERNAL,
                ignoreCase: true,
              );
    }
  }

  checkAndRequestPermissions({bool retry = false}) async {
    // The param 'retryRequest' is false, by default.
    _hasPermission =
        await context.read<AppController>().audioQuery.checkAndRequest(
              retryRequest: retry,
            );
    // Only call update the UI if application has all required permissions.
    _hasPermission ? setState(() {}) : null;
  }

  Widget noAccessToLibraryWidget() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.redAccent.withOpacity(0.5),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Application doesn't have access to the library"),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () => checkAndRequestPermissions(retry: true),
            child: const Text("Allow"),
          ),
        ],
      ),
    );
  }

  bool pPlay = false;
  @override
  Widget build(BuildContext context) {
    context
        .read<AppController>()
        .audioPlayer
        .androidAudioSessionIdStream
        .listen((event) {
      log("message: $event");
      Channel.setSessionId(event ?? 0);
    });
    return Consumer<AppController>(builder: (context, controller, child) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Musix"),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 18.0),
              child: IconButton(
                onPressed: () {
                  showSearch(context: context, delegate: SearchPage());
                },
                icon: const Icon(Icons.search),
              ),
            )
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(child: Text("Songs")),
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
                child: Text("Folders"),
              )
            ],
          ),
        ),
        body: GestureDetector(
          onScaleUpdate: (details) {
            print(details.scale);
          },
          child: TabBarView(
            controller: _tabController,
            children: const [
              AllSongs(),
              Artists(),
              Albums(),
              Genres(),
              Folders()
            ],
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: controller.audioPlayer.playing
            ? Container(
                margin: const EdgeInsets.only(left: 10, bottom: 40, right: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  color: Colors.white70,
                ),
                child: BottomPlayer(
                  controller: controller,
                ),
              )
            : null,
      );
    });
  }
}
