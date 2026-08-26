import '/exports/exports.dart';

import '../data/library_repository.dart';
import '/widgets/song_tile.dart';
import '/widgets/song_options_sheet.dart';
import '/Routes/routes.dart';
import '/controllers/app_controller.dart';

class Recents extends StatefulWidget {
  const Recents({super.key});

  @override
  State<Recents> createState() => _RecentsState();
}

class _RecentsState extends State<Recents> {
  late final Stream<List<SongModel>> _stream = context
      .read<LibraryRepository>()
      .watchSongs(sort: SongSort.dateAdded, dir: SortDir.desc);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SongModel>>(
      stream: _stream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        final songs = snap.data!;
        return Consumer<AppController>(
          builder: (context, controller, _) {
            return SongListView(
              songs: songs,
              controller: controller,
              onTap: (song, index) {
                controller.playSongFromList(songs, index);
                Routes.playerTo(context);
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
          },
        );
      },
    );
  }
}
