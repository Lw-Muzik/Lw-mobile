
import '/Global/index.dart';
import '/Routes/routes.dart';
import '/controllers/AppController.dart';
import '/extensions/index.dart';
import '/widgets/Body.dart';
import '/widgets/song_options_sheet.dart';
import '/widgets/song_tile.dart';
import '/exports/exports.dart';

import '../player/player_ui.dart';
import '../widgets/ArtworkWidget.dart';
import '../widgets/BottomPlayer.dart';
import '/data/library_repository.dart';

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
  late final Stream<List<SongModel>> _songsStream =
      context.read<LibraryRepository>().watchArtistSongs(widget.artist);

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
        Hero(
          tag: 'artist_${widget.artistId}',
          child: headerWidget(
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
                  style: Theme.of(context).textTheme.headlineLarge!.copyWith(
                    fontWeight: FontWeight.w300,
                  ),
                ),
                TextSpan(
                  text: widget.songs.aTracks,
                  style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                    fontWeight: FontWeight.w300,
                  ),
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
          body: StreamBuilder<List<SongModel>>(
            stream: _songsStream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator.adaptive(),
                );
              } else if (snapshot.data!.isNotEmpty) {
                final songs = snapshot.data!;
                return SongListView(
                  songs: songs,
                  controller: controller,
                  onTap: (song, index) {
                    controller.playSongFromList(songs, index);
                    Routes.routeTo(const Player(), context);
                  },
                  onLongPress: (song, index) {
                    showModalBottomSheet(
                      context: context,
                      builder: (_) => SongOptionsSheet(song: song),
                    );
                  },
                  onOptions: (song, index) {
                    showModalBottomSheet(
                      context: context,
                      builder: (_) => SongOptionsSheet(song: song),
                    );
                  },
                );
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
