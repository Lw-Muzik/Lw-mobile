import 'package:eq_app/Global/index.dart';
import 'package:eq_app/Helpers/Files.dart';
import 'package:eq_app/extensions/index.dart';
import 'package:eq_app/pages/ArtistSongs.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../controllers/AppController.dart';
import '../widgets/BottomPlayer.dart';

class PlaylistSongs extends StatefulWidget {
  final int playlist_id;
  final String playlist;
  final int songs;
  const PlaylistSongs(
      {super.key,
      required this.playlist_id,
      required this.playlist,
      required this.songs});

  @override
  State<PlaylistSongs> createState() => _PlaylistSongsState();
}

class _PlaylistSongsState extends State<PlaylistSongs> {
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
                      stream: Stream.fromFuture(OnAudioQuery().queryAudiosFrom(
                          AudiosFromType.PLAYLIST, widget.playlist_id)),
                      builder: (context, snapshot) {
                        return snapshot.hasData
                            ? Consumer<AppController>(
                                builder: (context, controller, child) {
                                return snapshot.data!.isNotEmpty
                                    ? headerWidget(controller, context,
                                        data: snapshot.data!)
                                    : Container();
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
                            text: "${widget.playlist}\n",
                            style: Theme.of(context).textTheme.displayMedium,
                          ),
                          TextSpan(
                            text: "${widget.songs}",
                            style: Theme.of(context)
                                .textTheme
                                .headlineLarge!
                                .copyWith(fontWeight: FontWeight.w300),
                          ),
                          TextSpan(
                            text: widget.songs.aTracks,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall!
                                .copyWith(fontWeight: FontWeight.w300),
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
          body: Stack(
            children: [
              StreamBuilder(
                stream: Stream.fromFuture(OnAudioQuery().queryAudiosFrom(
                    AudiosFromType.PLAYLIST, widget.playlist_id)),
                builder: (context, snap) {
                  return snap.hasData
                      ? SongLists(songs: snap.data ?? [])
                      : const Center(
                          child: CircularProgressIndicator.adaptive());
                },
              ),
              if (controller.audioPlayer.playing)
                Positioned(
                  bottom: 0,
                  right: 3,
                  left: 3,
                  child: BottomPlayer(
                    controller: controller,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}
