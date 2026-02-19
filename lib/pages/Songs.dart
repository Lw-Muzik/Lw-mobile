import '/exports/exports.dart';

import '/Helpers/Files.dart';
import '/widgets/song_tile.dart';
import '/widgets/PlayListWidget.dart';
import '/Routes/routes.dart';
import '/controllers/AppController.dart';
import '../player/PlayerUI.dart';

class AllSongs extends StatefulWidget {
  const AllSongs({super.key});

  @override
  State<AllSongs> createState() => _AllSongsState();
}

class _AllSongsState extends State<AllSongs> {
  final ScrollController scrollController = ScrollController();
  late Future<List<SongModel>> _songsFuture;

  @override
  void initState() {
    super.initState();
    _songsFuture = Files.fetchAllSongs();
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SongModel>>(
      future: _songsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        } else if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48,
                    color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 12),
                Text(
                  "Failed to load songs. Please try again.",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          );
        } else if (snap.hasData && snap.data!.isNotEmpty) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.music_note,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      "${snap.data!.length} songs",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Consumer<AppController>(
                  builder: (context, controller, _) {
                    return SongListView(
                      songs: snap.data!,
                      controller: controller,
                      onTap: (song, index) {
                        controller.playSongFromList(snap.data!, index);
                        Routes.routeTo(const Player(), context);
                      },
                      onLongPress: (song, index) {
                        showModalBottomSheet(
                          context: context,
                          builder: (context) => BottomSheet(
                            onClosing: () {},
                            builder: (context) => PlaylistWidget(
                              audioId: song.id,
                              song: song.title,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        } else {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.music_off, size: 64,
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                Text(
                  "No songs available.",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          );
        }
      },
    );
  }
}
