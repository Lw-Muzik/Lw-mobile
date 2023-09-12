import 'package:eq_app/Helpers/index.dart';
import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/extensions/index.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../controllers/AppController.dart';

class PlaylistWidget extends StatefulWidget {
  final int audioId;
  final String song;
  const PlaylistWidget({super.key, required this.audioId, required this.song});

  @override
  State<PlaylistWidget> createState() => _PlaylistWidgetState();
}

class _PlaylistWidgetState extends State<PlaylistWidget> {
  @override
  void initState() {
    super.initState();
  }

  final TextEditingController _textEditingController = TextEditingController();
  List<PlaylistModel> _list = [];
  @override
  Widget build(BuildContext context) {
    if (mounted) {
      OnAudioQuery().queryPlaylists().asStream().listen((event) {
        if (mounted) {
          setState(() {
            _list = event;
          });
        }
      });
    }

    // OnAudioQuery.platform.addToPlaylist(playlistId, audioId)//createPlaylist("")
    return Consumer<AppController>(builder: (context, controller, x) {
      return Card(
        child: ListView(
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
                        _textEditingController, controller, context),
                    icon: const Icon(Icons.add),
                  )
                ],
              ),
            ),
            if (_list.isNotEmpty)
              ...List.generate(
                _list.length,
                (index) => ListTile(
                  leading: const Icon(Icons.playlist_play),
                  title: Text(_list[index].playlist),
                  subtitle: Text(_list[index].numOfSongs.nSongs),
                  onTap: () {
                    controller.audioQuery
                        .addToPlaylist(_list[index].id, widget.audioId)
                        .then((value) {
                      showMessage(
                        context: context,
                        msg:
                            '${widget.song} added to ${_list[index].playlist} successfully',
                      );
                      Routes.pop(context);
                    });
                  },
                ),
              )
          ],
        ),
      );
    });
  }
}
