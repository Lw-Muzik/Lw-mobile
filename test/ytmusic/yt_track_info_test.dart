/// Track details for tagging a download, read from real `next` and lyrics
/// responses captured Oct 2026: a song (Burna Boy, "Last Last") and a music
/// video ("Killin Dem (feat. Zlatan)").
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/services/ytmusic/parse/yt_track_info.dart';

Object? fixture(String name) {
  final file = File('test/fixtures/ytmusic/$name.json.gz');
  return jsonDecode(utf8.decode(gzip.decode(file.readAsBytesSync())));
}

void main() {
  group('parseTrackInfo', () {
    test('a song: artist, album and its link, year, square art, lyrics', () {
      final info = parseTrackInfo(fixture('next_song'), '2cNFrajBk0k')!;
      expect(info.title, 'Last Last');
      expect(info.artist, 'Burna Boy');
      expect([for (final a in info.artists) (a.name, a.id)], [
        ('Burna Boy', 'UCr61sufuLt7_eB7ak1bXHIg'),
      ]);
      expect(info.album, 'Love, Damini');
      expect(info.albumId, 'MPREb_If75wr3HkMf');
      expect(info.year, 2022);
      expect(info.durationSecs, greaterThan(150));
      expect(info.thumbnail, contains('googleusercontent.com'));
      expect(info.thumbnail, contains('=w544-h544'));
      expect(info.lyricsId, 'MPLYt_If75wr3HkMf-7');
      expect(info.isSong, isTrue);
    });

    test('a video: no album, its thumbnail, greyed-out lyrics are none', () {
      final info = parseTrackInfo(fixture('next_video'), '_EfSs6-Pxx8')!;
      expect(info.title, 'Killin Dem (feat. Zlatan)');
      expect(info.artist, 'Burna Boy');
      expect(info.album, isNull, reason: 'views and likes are not an album');
      expect(info.year, isNull);
      expect(info.thumbnail, contains('i.ytimg.com'));
      expect(info.lyricsId, isNull);
      expect(info.isSong, isFalse);
    });

    test('a video id the response does not hold is null', () {
      expect(parseTrackInfo(fixture('next_song'), 'nope'), isNull);
      expect(parseTrackInfo(null, 'x'), isNull);
    });

    test('a video paired with its song takes the song\'s album and art', () {
      Map<String, Object?> row(String id, List<Map<String, Object?>> byline,
              {String? type, int size = 544}) =>
          {
            'videoId': id,
            'title': {
              'runs': [
                {'text': 'Song'},
              ],
            },
            'longBylineText': {'runs': byline},
            'thumbnail': {
              'thumbnails': [
                {'url': 'https://x/$id', 'width': size, 'height': size},
              ],
            },
            'navigationEndpoint': {
              'watchEndpoint': {
                'watchEndpointMusicSupportedConfigs': {
                  'watchEndpointMusicConfig': {'musicVideoType': type},
                },
              },
            },
            'selected': true,
          };
      final json = {
        'playlistPanelVideoWrapperRenderer': {
          'primaryRenderer': {
            'playlistPanelVideoRenderer': row('vid', [
              {'text': 'Artist'},
              {'text': ' • '},
              {'text': '1M views'},
            ], type: 'MUSIC_VIDEO_TYPE_OMV'),
          },
          'counterpart': [
            {
              'counterpartRenderer': {
                'playlistPanelVideoRenderer': row('song', [
                  {'text': 'Artist'},
                  {'text': ' • '},
                  {
                    'text': 'The Album',
                    'navigationEndpoint': {
                      'browseEndpoint': {'browseId': 'MPREb_x'},
                    },
                  },
                  {'text': ' • '},
                  {'text': '2019'},
                ], type: 'MUSIC_VIDEO_TYPE_ATV'),
              },
            },
          ],
        },
      };
      final info = parseTrackInfo(json, 'vid')!;
      expect(info.album, 'The Album');
      expect(info.albumId, 'MPREb_x');
      expect(info.year, 2019);
      expect(info.thumbnail, 'https://x/song');
      expect(info.isSong, isTrue);
    });
  });

  group('parseLyrics', () {
    test('the text with its line breaks, and who supplied it', () {
      final lyrics = parseLyrics(fixture('lyrics'))!;
      expect(lyrics.text, startsWith('(E don cast)\n(Last, last)'));
      expect(lyrics.text.split('\n').length, greaterThan(50));
      expect(lyrics.source, 'Musixmatch');
    });

    test('no shelf is no lyrics', () {
      expect(parseLyrics({'contents': {}}), isNull);
    });
  });
}
