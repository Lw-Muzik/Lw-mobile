// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

import '../Routes/routes.dart';
import '../controllers/AppController.dart';

String tempPath = "";

Future<ImageProvider<Object>> fetchArtwork(
  String path,
  int id, {
  ArtworkType type = ArtworkType.AUDIO,
  String other = "",
  int quality = 100,
  int size = 2000,
}) async {
  var tempDir = await getTemporaryDirectory();
  String imagePath = "";
  tempPath = tempDir.path;
  //
  var albumPath = Directory("$tempPath/Albums");
  if (albumPath.existsSync() == false) {
    await albumPath.create();
    log("Albums ${albumPath.path}");
  }
  //
  var artistPath = Directory("$tempPath/Artists");
  if (artistPath.existsSync() == false) {
    await artistPath.create();
    log("Artist ${artistPath.path}");
  }

  //
  var genrePath = Directory("$tempPath/Genres");
  if (genrePath.existsSync() == false) {
    await genrePath.create();
    log("Genres ${genrePath.path}");
  }

  if (path.isEmpty && other != "Unknown") {
    log("here");
    if (type == ArtworkType.ALBUM) {
      imagePath =
          "${albumPath.path}/${other.replaceFirst(' ', '_').replaceFirst('/', '_')}.png";
    } else if (type == ArtworkType.ARTIST) {
      imagePath =
          "${artistPath.path}/${other.replaceFirst(' ', '_').replaceFirst('/', '_')}.png";
    } else if (type == ArtworkType.GENRE) {
      imagePath =
          "${genrePath.path}/${other.replaceFirst(' ', '_').replaceFirst('/', '_')}.png";
    }
  } else {
    imagePath = "$tempPath/${path.split("/").last.split(".").first}.png";
  }
  if (File(imagePath).existsSync() == false) {
    //  fetch artwork from songs
    Uint8List? artworkData = await OnAudioQuery.platform.queryArtwork(
      id,
      type,
      quality: quality,
      size: size,
      format: ArtworkFormat.PNG,
    );

    if (tempPath.isNotEmpty && artworkData != null && artworkData.isNotEmpty) {
      // ID3Tag tags = ID3TagReader.path(path).readTagSync();

      // check if metadata is not null and path of the artwork exists

      File(imagePath).writeAsBytesSync(artworkData);
    }
  }
  log("Current Path $imagePath");
  return File(imagePath).existsSync()
      ? FileImage(File(imagePath))
      : const AssetImage("assets/audio.jpeg") as ImageProvider;
}

/// show snackbar message
/// @param type = 'danger' | 'info' | warning
///
///
void showMessage(
    {String type = 'info',
    String? msg,
    bool float = false,
    required BuildContext context,
    double opacity = 1,
    int duration = 5,
    Animation<double>? animation}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: float ? SnackBarBehavior.floating : SnackBarBehavior.fixed,
      content: Text(msg ?? ''),
      backgroundColor: type == 'info'
          ? Theme.of(context).colorScheme.primary
          : type == 'warning'
              ? const Color.fromARGB(255, 255, 155, 73)!.withOpacity(opacity)
              : type == 'danger'
                  ? const Color.fromARGB(255, 247, 68, 68)!.withOpacity(opacity)
                  : type == 'success'
                      ? Color.fromARGB(255, 20, 238, 31).withOpacity(opacity)
                      : Colors.grey[600]!.withOpacity(opacity),
      duration: Duration(seconds: duration),
    ),
  );
}

// show add playlist widget
void showAddPlaylist(TextEditingController textController,
    AppController controller, BuildContext context) {
  showAdaptiveDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text("Create playlist"),
          children: [
            TextField(
              showCursor: true,
              autofocus: true,
              controller: textController,
              decoration: const InputDecoration(
                hintText: "Enter playlist name",
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    if (textController.text.isNotEmpty) {
                      controller.audioQuery
                          .createPlaylist(textController.text)
                          .then((value) {
                        if (value) {
                          showMessage(
                              context: context,
                              float: true,
                              type: "success",
                              msg:
                                  "${textController.text} created successfully");
                          textController.clear();
                          Routes.pop(context);
                        }
                      });
                    } else {
                      showMessage(
                          context: context,
                          float: true,
                          msg: "Playlist name is required");
                      Routes.pop(context);
                      Routes.pop(context);
                    }
                  },
                  child: const Text("Create"),
                ),
                TextButton(
                  onPressed: () => Routes.pop(context),
                  child: const Text("Cancel"),
                ),
              ],
            )
          ],
        );
      });
}

void showDeletePlaylist(AppController controller, String playlist,
    int playlist_id, BuildContext context) {
  showAdaptiveDialog(
      context: context,
      builder: (context) {
        return AlertDialog.adaptive(
          title: const Text("Remove playlist!!"),
          content: Text("Are you sure you want to remove $playlist"),
          actions: [
            TextButton(
              onPressed: () => Routes.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                Routes.pop(context);
                controller.audioQuery
                    .removePlaylist(
                  playlist_id,
                )
                    .then((value) {
                  if (value) {
                    showMessage(
                        context: context,
                        msg: "$playlist removed successfully");
                  }
                });
              },
              child: const Text("Delete"),
            )
          ],
        );
      });
}
