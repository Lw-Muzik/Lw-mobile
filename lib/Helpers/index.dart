// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:math';

import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

String tempPath = "";
String imagePath = "";
File fetchArtwork(String path, int id, {ArtworkType type = ArtworkType.AUDIO}) {
  getTemporaryDirectory().then((value) {
    tempPath = value.path;
    // File file = File();
    String imagePath = "$tempPath/${path.split("/").last.split(".").first}.png";
    if (tempPath.isNotEmpty && (path.endsWith("mp3") || path.endsWith("m4a"))) {
      // ID3Tag tags = ID3TagReader.path(path).readTagSync();
      OnAudioQuery.platform
          .queryArtwork(id, type,
              quality: 100, size: 2000, format: ArtworkFormat.PNG)
          .then(
        (meta) {
          if ((File(imagePath).existsSync() == false) && (meta!.isNotEmpty)) {
            File(imagePath).writeAsBytesSync(meta);
          }
        },
      );
    }
  });

  return File(imagePath);
}
