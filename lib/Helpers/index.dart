// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

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
    if (type == ArtworkType.ALBUM) {
      imagePath = "${albumPath.path}/$other.png";
    } else if (type == ArtworkType.ARTIST) {
      imagePath = "${artistPath.path}/$other.png";
    } else if (type == ArtworkType.GENRE) {
      imagePath = "${genrePath.path}/$other.png";
    }
  } else {
    imagePath = "$tempPath/${path.split("/").last.split(".").first}.png";
  }
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
    if (File(imagePath).existsSync() == false) {
      File(imagePath).writeAsBytesSync(artworkData);
    }
  }
  log("Current Path $imagePath");
  return File(imagePath).existsSync()
      ? FileImage(File(imagePath))
      : const AssetImage("assets/audio.jpeg") as ImageProvider;
}
