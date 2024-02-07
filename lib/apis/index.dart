// ignore_for_file: use_build_context_synchronously

import 'dart:io';

import 'package:eq_app/Helpers/index.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:path_provider/path_provider.dart';
import '../Routes/routes.dart';
import '../models/ArtworkModel.dart';

class Apis {
  static String devUrl = "http://15.237.71.190:5054";
  static String artwork = "$devUrl/get/songImage/";
  static String fetchLyrics = "$devUrl/get/songLyrics/";

  static Future<ArtworkModel> fetchArtWork(String title, String artist) async {
    var res = await Client().get(Uri.parse("$artwork$title/$artist"));
    return artworkModelFromJson(res.body);
  }

  static void downloadArtwork(
    String url,
    String path,
    BuildContext context,
  ) async {
    var res = await Client().readBytes(Uri.parse(url));
    var tempDir = await getTemporaryDirectory();
    String tempPath = tempDir.path;
    String image = "$tempPath/${path.split('/').last.split('.').first}.png";
    if (File(image).existsSync() == true) {
      File(image).deleteSync(recursive: true);
    }
    await File(image).writeAsBytes(res);
    // AudioTags.write(
    //   path,
    //   Tag(
    //     pictures: [
    //       Picture(
    //         bytes: res,
    //         pictureType: PictureType.coverFront,
    //         mimeType: MimeType.jpeg,
    //       ),
    //     ],
    //   ),
    // ).then((value) {
    showMessage(context: context, type: "success", msg: "Artwork Downloaded");
    Routes.pop(context);
    // });
  }
}
