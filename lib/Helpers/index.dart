// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
// import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:id3tag/id3tag.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

import '../Routes/routes.dart';
import '../controllers/AppController.dart';

String tempPath = "";

Future<void> fetchArtwork(
  String path,
  int id, {
  ArtworkType type = ArtworkType.AUDIO,
  String other = "",
  int quality = 70,
  int size = 200,
}) async {
  String tempPath = "";

  var tempDir = await getTemporaryDirectory();
  tempPath = tempDir.path;
  // }

  String imagePath = "";

  Future<Directory> createDirectory(Directory dir) async {
    if (!dir.existsSync()) {
      return await dir.create(recursive: true);
    }
    return dir;
  }

  String getArtworkImagePath() {
    if (path.isEmpty && other.isNotEmpty) {
      return "$tempPath/${other.replaceAll(RegExp(r'[ /|:]'), '_')}.png";
    } else {
      return "$tempPath/${path.split('/').last.split('.').first}.png";
    }
  }
// function to fetch saveImage Urls

  Future<void> saveArtworkImage(String imgPath, String original) async {
    if (!File(imgPath).existsSync()) {
      if (type == ArtworkType.ALBUM ||
          type == ArtworkType.ARTIST ||
          type == ArtworkType.GENRE) {
        var artworkData = await OnAudioQuery()
            .queryArtwork(id, type, quality: quality, size: 500);
        if (artworkData != null && artworkData.isNotEmpty) {
          await File(imgPath).writeAsBytes(artworkData);
        }
      } else if (type == ArtworkType.AUDIO) {
        if (File(original).existsSync()) {
          var parser = ID3TagReader.path(original);
          var tag = await parser.readTag();
          var artworkData = tag.pictures;
          if (tempPath.isNotEmpty && artworkData.isNotEmpty) {
            await File(imgPath).writeAsBytes(artworkData.first.imageData);
          }
        }
      }
    }
  }

  Directory albumPath = await createDirectory(Directory("$tempPath/Albums"));
  Directory artistPath = await createDirectory(Directory("$tempPath/Artists"));
  Directory genrePath = await createDirectory(Directory("$tempPath/Genres"));
  if (path.isEmpty && other != "Unknown") {
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
    imagePath = getArtworkImagePath();
  }
  await saveArtworkImage(imagePath, path);
}

Future<ImageProvider<Object>> savedImage(
  String path,
  int id, {
  ArtworkType type = ArtworkType.AUDIO,
  String other = "",
  int quality = 70,
  int size = 200,
}) async {
  String tempPath = "";
  String imagePath = "";

  var tempDir = await getTemporaryDirectory();
  tempPath = tempDir.path;

  String getArtworkImagePath() {
    if (path.isEmpty && other.isNotEmpty) {
      return "$tempPath/${other.replaceAll(RegExp(r'[ /|:]'), '_')}.png";
    } else {
      return "$tempPath/${path.split('/').last.split('.').first}.png";
    }
  }

  if (path.isEmpty && other != "Unknown") {
    if (type == ArtworkType.ALBUM) {
      imagePath =
          "$tempPath/Albums/${other.replaceFirst(' ', '_').replaceFirst('/', '_')}.png";
    } else if (type == ArtworkType.ARTIST) {
      imagePath =
          "$tempPath/Artists/${other.replaceFirst(' ', '_').replaceFirst('/', '_')}.png";
    } else if (type == ArtworkType.GENRE) {
      imagePath =
          "$tempPath/Genres/${other.replaceFirst(' ', '_').replaceFirst('/', '_')}.png";
    }
  } else {
    imagePath = getArtworkImagePath();
  }
  Future.delayed(const Duration(seconds: 1));
  return File(imagePath).existsSync()
      ? FileImage(
          File(imagePath),
        )
      : const AssetImage("assets/audio.jpeg") as ImageProvider;
}

// function to fetch saved artwork to work on the notification
Future<String> fetchArtworkUrl(
  String path,
  int id, {
  ArtworkType type = ArtworkType.AUDIO,
  String other = "",
  int quality = 90,
  int size = 400,
}) async {
  final tempDir = await getTemporaryDirectory();
  final tempPath = tempDir.path;
  String imagePath = "";

  getArtworkImagePath() {
    if (path.isEmpty && other.isNotEmpty && other != "Unknown") {
      return "$tempPath/${other.replaceAll(RegExp(r'[ /]'), '_')}.png";
    } else {
      return "$tempPath/${path.split('/').last.split('.').first}.png";
    }
  }

  imagePath = getArtworkImagePath();
  final dirD = Directory("$tempPath/Default");
  if (!dirD.existsSync()) {
    await dirD.create(recursive: true);
    final defaultImg = await rootBundle.load("assets/audio.jpeg");
    await File("${dirD.path}/default.png")
        .writeAsBytes(defaultImg.buffer.asUint8List());
  }

  return File(imagePath).existsSync() ? imagePath : "${dirD.path}/default.png";
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
              ? const Color.fromARGB(255, 255, 155, 73).withOpacity(opacity)
              : type == 'danger'
                  ? const Color.fromARGB(255, 247, 68, 68).withOpacity(opacity)
                  : type == 'success'
                      ? const Color.fromARGB(255, 20, 238, 31)
                          .withOpacity(opacity)
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
                          // controller.audioQuery.addToPlaylist()
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
    int playlistId, BuildContext context) {
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
                  playlistId,
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

String formatTime(Duration time) {
  return "${RegExp(r'((^0*[1-9]\d*:)?\d{2}:\d{2})\.\d+$').firstMatch("$time")?.group(1)}";
}
