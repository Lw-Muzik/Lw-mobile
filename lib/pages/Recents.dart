import '/exports/exports.dart';

import '../Helpers/Files.dart';
import '/widgets/song_tile.dart';
import '/widgets/song_options_sheet.dart';
import '/Routes/routes.dart';
import '/controllers/AppController.dart';
import '../player/player_ui.dart';

class Recents extends StatefulWidget {
  const Recents({super.key});

  @override
  State<Recents> createState() => _RecentsState();
}

class _RecentsState extends State<Recents> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SongModel>>(
      future: Files.fetchMostRecentlyPlayed(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        return Consumer<AppController>(
          builder: (context, controller, _) {
            return SongListView(
              songs: snap.data ?? [],
              controller: controller,
              onTap: (song, index) {
                controller.playSongFromList(snap.data!, index);
                Routes.routeTo(const Player(), context);
              },
              onLongPress: (song, index) {
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
