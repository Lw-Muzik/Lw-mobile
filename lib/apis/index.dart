// ignore_for_file: use_build_context_synchronously

import 'dart:io';

import 'package:eq_app/Helpers/index.dart';
import 'package:eq_app/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:path_provider/path_provider.dart';
import '../Routes/routes.dart';
import '../models/ArtworkModel.dart';

class Apis {
  static String get _baseUrl => AppConfig.apiBaseUrl;
  static String get artwork => "$_baseUrl/get/songImage/";
  static String get fetchLyrics => "$_baseUrl/get/songLyrics/";

  static final Client _client = Client();
  static const Duration _timeout = Duration(seconds: 15);

  static Future<ArtworkModel> fetchArtWork(String title, String artist) async {
    try {
      final res = await _client
          .get(Uri.parse("$artwork$title/$artist"))
          .timeout(_timeout);
      return artworkModelFromJson(res.body);
    } catch (e) {
      debugPrint('Error fetching artwork: $e');
      rethrow;
    }
  }

  static Future<void> downloadArtwork(
    String url,
    String path,
    BuildContext context,
  ) async {
    try {
      final res = await _client.readBytes(Uri.parse(url)).timeout(_timeout);
      final tempDir = await getTemporaryDirectory();
      final tempPath = tempDir.path;
      final image =
          "$tempPath/${path.split('/').last.split('.').first}.png";
      final file = File(image);
      if (file.existsSync()) {
        file.deleteSync(recursive: true);
      }
      await file.writeAsBytes(res);
      showMessage(
          context: context, type: "success", msg: "Artwork Downloaded");
      Routes.pop(context);
    } catch (e) {
      debugPrint('Error downloading artwork: $e');
      showMessage(
          context: context, type: "danger", msg: "Failed to download artwork");
    }
  }
}
