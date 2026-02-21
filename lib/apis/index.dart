// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
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

  /// Fetches lyrics text from the backend API. Returns null on failure.
  static Future<String?> fetchLyricsData(String title, String artist) async {
    try {
      final uri = Uri.parse(
        "$fetchLyrics${Uri.encodeComponent(title)}/${Uri.encodeComponent(artist)}",
      );
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        return res.body;
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching lyrics: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // LRCLIB lyrics search (https://lrclib.net)
  // ---------------------------------------------------------------------------

  static const _lrclibHeaders = {'User-Agent': 'HypeMuzik/1.0'};

  /// Fetches lyrics from LRCLIB.net.
  /// Tries exact match first, then falls back to scored search.
  /// Returns raw LRC/plain text or null.
  static Future<String?> fetchLyricsFromLrclib({
    required String title,
    required String artist,
    int? durationMs,
  }) async {
    final result = await _lrclibSearch(title, artist, durationMs);
    return result;
  }

  /// Exact match via GET /api/get with structured parameters.
  // static Future<String?> _lrclibExactMatch(
  //   String title,
  //   String artist,
  //   int? durationMs,
  // ) async {
  //   try {
  //     final params = <String, String>{
  //       'track_name': title,
  //       'artist_name': artist,
  //     };
  //     if (durationMs != null) {
  //       params['duration'] = (durationMs / 1000).round().toString();
  //     }
  //     final uri = Uri.https('lrclib.net', '/api/get', params);
  //     final res = await _client
  //         .get(uri, headers: _lrclibHeaders)
  //         .timeout(_timeout);
  //     if (res.statusCode == 200) {
  //       final json = jsonDecode(res.body) as Map<String, dynamic>;
  //       if (json['instrumental'] == true) return null;
  //       return json['syncedLyrics'] as String? ??
  //           json['plainLyrics'] as String?;
  //     }
  //   } catch (e) {
  //     debugPrint('LRCLIB exact match error: $e');
  //   }
  //   return null;
  // }

  /// Scored search via GET /api/search?q=... — picks best match by artist,
  /// title, duration proximity, and synced availability.
  static Future<String?> _lrclibSearch(
    String title,
    String artist,
    int? durationMs,
  ) async {
    try {
      final query = title; //artist.isNotEmpty ? '$title $artist' : title;
      final uri = Uri.https('lrclib.net', '/api/search', {'q': query});
      final res = await _client
          .get(uri, headers: _lrclibHeaders)
          .timeout(_timeout);
      if (res.statusCode != 200) return null;

      final results = (jsonDecode(res.body) as List)
          .cast<Map<String, dynamic>>();
      if (results.isEmpty) return null;

      final durationSec = durationMs != null ? durationMs / 1000.0 : null;
      final artistLower = artist.toLowerCase().trim();
      final titleLower = title.toLowerCase().trim();

      Map<String, dynamic>? best;
      int bestScore = -1;

      for (final r in results) {
        if (r['instrumental'] == true) continue;

        final rArtist = (r['artistName'] as String? ?? '').toLowerCase();
        final rTitle = (r['trackName'] as String? ?? '').toLowerCase();

        // Title MUST match — skip entirely if no title relevance
        bool titleMatched = false;
        int score = 0;
        if (rTitle == titleLower) {
          score += 10;
          titleMatched = true;
        } else if (rTitle.contains(titleLower) ||
            titleLower.contains(rTitle)) {
          score += 5;
          titleMatched = true;
        }
        if (!titleMatched) continue;

        // Artist match (required when artist info is available)
        bool artistMatched = artistLower.isEmpty;
        if (artistLower.isNotEmpty) {
          if (rArtist == artistLower) {
            score += 10;
            artistMatched = true;
          } else if (rArtist.contains(artistLower) ||
              artistLower.contains(rArtist)) {
            score += 5;
            artistMatched = true;
          }
        }
        if (!artistMatched) continue;

        // Duration proximity
        if (durationSec != null && r['duration'] != null) {
          final diff =
              ((r['duration'] as num).toDouble() - durationSec).abs();
          if (diff <= 2) {
            score += 5;
          } else if (diff <= 5) {
            score += 3;
          } else if (diff <= 10) {
            score += 1;
          }
        }

        // Synced lyrics bonus
        if (r['syncedLyrics'] != null) score += 3;

        if (score > bestScore) {
          bestScore = score;
          best = r;
        }
      }

      if (best == null) return null;
      return best['syncedLyrics'] as String? ??
          best['plainLyrics'] as String?;
    } catch (e) {
      debugPrint('LRCLIB search error: $e');
    }
    return null;
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
      final image = "$tempPath/${path.split('/').last.split('.').first}.png";
      final file = File(image);
      if (file.existsSync()) {
        file.deleteSync(recursive: true);
      }
      await file.writeAsBytes(res);
      showMessage(context: context, type: "success", msg: "Artwork Downloaded");
      Routes.pop(context);
    } catch (e) {
      debugPrint('Error downloading artwork: $e');
      showMessage(
        context: context,
        type: "danger",
        msg: "Failed to download artwork",
      );
    }
  }
}
