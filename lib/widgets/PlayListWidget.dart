import '/extensions/index.dart';
import '/Helpers/index.dart';
import '/Routes/routes.dart';
import '/exports/exports.dart';

import '../controllers/AppController.dart';

class PlaylistWidget extends StatefulWidget {
  final int audioId;
  final String song;
  const PlaylistWidget({super.key, required this.audioId, required this.song});

  @override
  State<PlaylistWidget> createState() => _PlaylistWidgetState();
}

class _PlaylistWidgetState extends State<PlaylistWidget> {
  late Future<List<PlaylistModel>> _playlistFuture;
  final TextEditingController _textEditingController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _playlistFuture = OnAudioQuery().queryPlaylists();
  }

  @override
  void dispose() {
    _textEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, x) {
        return Card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(18.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Select playlist",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    IconButton.outlined(
                      onPressed: () => showAddPlaylist(
                        _textEditingController,
                        controller,
                        context,
                      ),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<PlaylistModel>>(
                  future: _playlistFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator.adaptive());
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Center(
                        child: Text(
                          "No playlists available",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    }

                    final list = snapshot.data!;
                    return ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          leading: const Icon(Icons.playlist_play),
                          title: Text(list[index].playlist),
                          subtitle: Text(list[index].numOfSongs.nSongs),
                          onTap: () {
                            controller.audioQuery
                                .addToPlaylist(
                                    list[index].id, widget.audioId)
                                .then((value) {
                              showMessage(
                                context: context,
                                msg:
                                    '${widget.song} added to ${list[index].playlist} successfully',
                              );
                              Routes.pop(context);
                            });
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
