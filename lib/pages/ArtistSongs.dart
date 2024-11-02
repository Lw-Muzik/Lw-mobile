import 'dart:ui';

import '/Global/index.dart';
import '/Routes/routes.dart';
import '/controllers/AppController.dart';
import '/extensions/index.dart';
import '/widgets/Body.dart';
import '/widgets/PlayListWidget.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../Helpers/index.dart';
import '../player/PlayerUI.dart';
import '../widgets/ArtworkWidget.dart';
import '../widgets/BottomPlayer.dart';

class ArtistSongs extends StatefulWidget {
  final int? artistId;
  final int songs;
  final int albums;
  final String artist;

  const ArtistSongs({
    super.key,
    required this.artistId,
    required this.artist,
    required this.songs,
    required this.albums,
  });

  @override
  State<ArtistSongs> createState() => _ArtistSongsState();
}

class _ArtistSongsState extends State<ArtistSongs> {
  @override
  Widget build(BuildContext context) {
    return Body(
      child: NestedScrollView(
        floatHeaderSlivers: true,
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _buildSliverAppBar(),
        ],
        body: Consumer<AppController>(
          builder: (context, controller, child) => _buildSongList(controller),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 400,
      leading: IconButton.filledTonal(
        onPressed: () => Routes.pop(context),
        icon: const Icon(Icons.arrow_back),
      ),
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        title: _buildArtistTitleCard(),
        expandedTitleScale: 70,
        background: _buildArtistBackground(),
      ),
    );
  }

  Widget _buildArtistTitleCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(5.0),
        child: Text(
          widget.artist,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
  }

  Widget _buildArtistBackground() {
    return Stack(
      children: [
        headerWidget(
          context.read<AppController>(),
          context,
          child: ArtworkWidget(
            borderRadius: BorderRadius.zero,
            size: 5000,
            quality: 100,
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.width,
            songId: widget.artistId!,
            other: widget.artist,
            type: ArtworkType.ARTIST,
          ),
        ),
        Positioned(
          bottom: 45,
          left: 20,
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: "${widget.artist}\n",
                  style: Theme.of(context).textTheme.titleLarge,
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
        ),
      ],
    );
  }

  Widget _buildSongList(AppController controller) {
    return StreamBuilder(
      stream: controller.handler.player.playingStream,
      builder: (context, service) {
        return Scaffold(
          body: FutureBuilder(
            future: OnAudioQuery.platform.queryAudiosFrom(
              AudiosFromType.ARTIST_ID,
              widget.artistId ?? 0,
              ignoreCase: true,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator.adaptive());
              } else if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                return SongLists(songs: snapshot.data!);
              } else {
                return const Center(child: Text("No songs found"));
              }
            },
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerDocked,
          bottomNavigationBar: service.data ?? false
              ? BottomPlayer(controller: controller)
              : null,
        );
      },
    );
  }
}

class SongLists extends StatelessWidget {
  final List<SongModel> songs;

  const SongLists({super.key, required this.songs});

  @override
  Widget build(BuildContext context) {
    return songs.isEmpty
        ? Center(
            child: Text(
              "No songs found",
              style: Theme.of(context).textTheme.titleMedium,
            ),
          )
        : ListView.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              return _buildSongItem(context, index);
            },
          );
  }

  Widget _buildSongItem(BuildContext context, int index) {
    return Consumer<AppController>(
      builder: (context, controller, _) {
        final song = songs[index];
        return Routes.animateTo(
          closedWidget: InkWell(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: commonDeration(controller, index, context),
              child: ListTile(
                selected: controller.songId == index,
                selectedTileColor:
                    Theme.of(context).primaryColor.withOpacity(0.1),
                selectedColor: Theme.of(context).primaryColorLight,
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium!,
                ),
                subtitle: Text(
                  song.artist ?? "No Artist",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  "${formatTime(Duration(milliseconds: song.duration ?? 0))} | ${song.fileExtension}",
                ),
                onTap: () {
                  _playSelectedSong(controller, context, song);
                },
                onLongPress: () =>
                    _showPlaylistOptions(context, controller, song),
                leading: ArtworkWidget(
                  height: 60,
                  width: 60,
                  songId: song.id,
                  path: song.data,
                  type: ArtworkType.AUDIO,
                ),
              ),
            ),
          ),
          openWidget: const Player(),
        );
      },
    );
  }

  void _playSelectedSong(
      AppController controller, BuildContext context, SongModel song) {
    controller.songs = songs;
    controller.songId = songs.indexOf(song);
    loadAudioSource(controller.handler, song);
    Routes.routeTo(const Player(), context);
  }

  void _showPlaylistOptions(
      BuildContext context, AppController controller, SongModel song) {
    showModalBottomSheet(
      context: context,
      builder: (context) => BottomSheet(
        onClosing: () {},
        builder: (context) {
          return PlaylistWidget(
            audioId: song.id,
            song: song.title,
          );
        },
      ),
    );
  }
}
