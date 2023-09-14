import 'package:eq_app/Global/index.dart';
import 'package:eq_app/Helpers/Files.dart';
import 'package:eq_app/pages/ArtistSongs.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../controllers/AppController.dart';
import '../widgets/BottomPlayer.dart';

class FolderSongs extends StatefulWidget {
  final String path;
  const FolderSongs({super.key, required this.path});

  @override
  State<FolderSongs> createState() => _FolderSongsState();
}

class _FolderSongsState extends State<FolderSongs> {
  int songs = 0;
  @override
  void initState() {
    super.initState();
    Files.queryFromFolder(widget.path).then((value) {
      setState(() {
        songs = value.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return NestedScrollView(
      headerSliverBuilder: (context, h) {
        return [
          SliverAppBar(
            forceMaterialTransparency: context.watch<AppController>().isFancy,
            expandedHeight: 400,
            shadowColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: true,
              background: Stack(
                children: [
                  StreamBuilder<List<SongModel>>(
                      stream:
                          Stream.fromFuture(Files.queryFromFolder(widget.path)),
                      builder: (context, snapshot) {
                        return snapshot.hasData
                            ? Consumer<AppController>(
                                builder: (context, controller, child) {
                                return headerWidget(controller, context,
                                    data: snapshot.data!);
                              })
                            : Container();
                      }),
                  Positioned(
                    bottom: 45,
                    left: 10,
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: "${widget.path.split("/").last}\n",
                            style: Theme.of(context).textTheme.displayMedium,
                          ),
                          TextSpan(
                            text: "$songs",
                            style: Theme.of(context)
                                .textTheme
                                .headlineLarge!
                                .copyWith(fontWeight: FontWeight.w300),
                          ),
                          TextSpan(
                            text: songs == 1
                                ? " Available Track\n"
                                : " Available Tracks\n",
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall!
                                .copyWith(fontWeight: FontWeight.w300),
                          ),
                          TextSpan(
                            text: widget.path,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall!
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  )
                ],
              ),
              // title: ,
            ),
          )
        ];
      },
      body: Consumer<AppController>(builder: (context, controller, child) {
        return Scaffold(
          backgroundColor: controller.isFancy
              ? Colors.transparent
              : Theme.of(context).scaffoldBackgroundColor,
          body: StreamBuilder(
            stream: Stream.fromFuture(Files.queryFromFolder(widget.path)),
            builder: (context, snap) {
              return snap.hasData
                  ? SongLists(songs: snap.data ?? [])
                  : const Center(child: CircularProgressIndicator.adaptive());
            },
          ),
          bottomNavigationBar: controller.audioPlayer.playing
              ? BottomPlayer(
                  controller: controller,
                )
              : null,
        );
      }),
    );
  }
}
