import 'package:eq_app/Global/index.dart';
import 'package:eq_app/Routes/routes.dart';
import '/exports/exports.dart';

import '../controllers/AppController.dart';
import '../player/PlayerUI.dart';
import '../widgets/ArtworkWidget.dart';

class SearchPage extends SearchDelegate<SongModel> {
  @override
  String get searchFieldLabel => "Search by title, artist, album";

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(onPressed: () => query = "", icon: const Icon(Icons.close)),
  ];

  @override
  Widget? buildLeading(BuildContext context) => InkWell(
    child: const Icon(Icons.arrow_back_ios_new),
    onTap: () => Routes.pop(context),
  );

  @override
  Widget buildResults(BuildContext context) {
    return _buildSongList(context, query);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSongList(context, query);
  }

  Widget _buildSongList(BuildContext context, String query) {
    final controller = Provider.of<AppController>(context, listen: false);
    final songs = _filterSongs(controller, query);

    if (songs.isEmpty) {
      return const Center(child: Text("No songs found"));
    }

    return ListView.builder(
      itemCount: songs.length,
      itemBuilder: (context, i) {
        return ListTile(
          onTap: () => _playSong(context, controller, songs[i]),
          leading: ArtworkWidget(
            songId: songs[i].id,
            type: ArtworkType.AUDIO,
            path: songs[i].data,
          ),
          title: Text(songs[i].title),
          subtitle: Text(songs[i].artist ?? "Unknown artist"),
        );
      },
    );
  }

  List<SongModel> _filterSongs(AppController controller, String query) {
    if (query.isEmpty) return controller.songs;

    final lowerQuery = query.toLowerCase();
    return controller.songs.where((song) {
      return song.title.toLowerCase().contains(lowerQuery) ||
          (song.artist?.toLowerCase().contains(lowerQuery) ?? false) ||
          (song.album?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }

  void _playSong(
    BuildContext context,
    AppController controller,
    SongModel song,
  ) {
    final songIndex = controller.songs.indexOf(song);
    if (songIndex != -1) {
      controller.playSongFromList(controller.songs, songIndex);
      Routes.routeTo(const Player(), context);
    }
  }
}
