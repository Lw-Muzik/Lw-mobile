/// The DASH manifest builder.
///
/// Built against `player_ios.json` — a real IOS-client response for a real music
/// video, which is the case that needs a manifest at all (no muxed format, no
/// HLS, 22 adaptive renditions).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:eq_app/services/ytmusic/parse/yt_dash.dart';
import 'package:eq_app/services/ytmusic/parse/yt_json.dart';

Object? fixture(String name) {
  final bytes =
      gzip.decode(File('test/fixtures/ytmusic/$name.json.gz').readAsBytesSync());
  return jsonDecode(utf8.decode(bytes));
}

void main() {
  late List<DashStream> video;
  late DashStream audio;

  setUpAll(() {
    final formats =
        ptr(fixture('player_ios'), 'streamingData/adaptiveFormats') as List;
    video = [];
    for (final format in formats) {
      final mime = ptrString(format, 'mimeType') ?? '';
      final stream = readStream(format);
      if (stream == null) continue;
      if (mime.startsWith('video/mp4') && mime.contains('avc1')) {
        video.add(stream);
      } else if (ptr(format, 'itag') == 140) {
        audio = stream;
      }
    }
  });

  test('reads every AVC rendition and the audio track', () {
    expect(video, isNotEmpty);
    expect(video.every((s) => s.codecs.startsWith('avc1')), isTrue);
    expect(video.every((s) => s.url.isNotEmpty), isTrue);
    // SegmentBase addressing is what lets a player seek inside one remote file.
    expect(video.every((s) => s.initRange.contains('-')), isTrue);
    expect(video.every((s) => s.indexRange.contains('-')), isTrue);
    expect(audio.itag, 140);
    expect(audio.audioSampleRate, greaterThan(0));
  });

  test('a format missing its byte ranges is refused, not guessed at', () {
    expect(
      readStream({
        'itag': 137,
        'url': 'https://example',
        'mimeType': 'video/mp4; codecs="avc1.640028"',
        'bitrate': 100,
      }),
      isNull,
    );
    // And a format with no codecs stated cannot be placed in an adaptation set.
    expect(
      readStream({
        'itag': 137,
        'url': 'https://example',
        'mimeType': 'video/mp4',
        'initRange': {'start': '0', 'end': '1'},
        'indexRange': {'start': '2', 'end': '3'},
      }),
      isNull,
    );
    expect(readStream(null), isNull);
    expect(readStream({'itag': 137}), isNull);
  });

  group('the manifest', () {
    late String manifest;

    setUpAll(() {
      manifest = buildDashManifest(
        video: video,
        audio: audio,
        duration: const Duration(seconds: 223, milliseconds: 958),
      );
    });

    test('is a static on-demand MPD stating its duration', () {
      expect(manifest, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(manifest, contains('urn:mpeg:dash:profile:isoff-on-demand:2011'));
      expect(manifest, contains('type="static"'));
      expect(manifest, contains('mediaPresentationDuration="PT223.958S"'));
      expect(manifest.trim(), endsWith('</MPD>'));
    });

    test('carries one adaptation set per media type', () {
      expect('mimeType="video/mp4"'.allMatches(manifest).length, 1);
      expect('mimeType="audio/mp4"'.allMatches(manifest).length, 1);
      expect('<Representation'.allMatches(manifest).length, video.length + 1);
    });

    test('every representation is addressable', () {
      expect('<SegmentBase indexRange="'.allMatches(manifest).length,
          video.length + 1);
      expect('<Initialization range="'.allMatches(manifest).length,
          video.length + 1);
      expect('<BaseURL>'.allMatches(manifest).length, video.length + 1);
    });

    test('renditions ascend by bandwidth', () {
      final bandwidths = RegExp(r'bandwidth="(\d+)"')
          .allMatches(manifest)
          .map((m) => int.parse(m.group(1)!))
          .toList();
      // The audio set follows the video set, so compare within the video run.
      final videoBandwidths = bandwidths.take(video.length).toList();
      expect(videoBandwidths, orderedEquals([...videoBandwidths]..sort()));
    });

    /// The one that silently breaks everything: a googlevideo URL is a long
    /// string of `&`-separated parameters, and an unescaped one makes the whole
    /// document invalid XML that the player rejects outright.
    test('escapes the URLs it embeds', () {
      expect(manifest, contains('&amp;'));
      expect(
        RegExp(r'&(?!amp;|lt;|gt;|quot;)').hasMatch(manifest),
        isFalse,
        reason: 'an unescaped & makes the manifest invalid XML',
      );
    });

    test('holds no video set when there are no video renditions', () {
      final audioOnly = buildDashManifest(
        video: const [],
        audio: audio,
        duration: const Duration(seconds: 10),
      );
      expect(audioOnly, isNot(contains('mimeType="video/mp4"')));
      expect(audioOnly, contains('mimeType="audio/mp4"'));
    });
  });
}
