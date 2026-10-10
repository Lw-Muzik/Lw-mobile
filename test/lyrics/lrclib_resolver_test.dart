import 'dart:convert';

import 'package:eq_app/services/lyrics/lrclib_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';

const _synced = '[00:01.00] I said ooh\n[00:04.00] I am blinded by the lights';

Map<String, dynamic> _hit(
  String track,
  String artist, {
  double duration = 200,
  String? synced = _synced,
  String? plain,
  bool instrumental = false,
}) => {
  'trackName': track,
  'artistName': artist,
  'duration': duration,
  'instrumental': instrumental,
  'syncedLyrics': synced,
  'plainLyrics': plain,
};

Response _json(Object body, [int status = 200]) => Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('normalizers', () {
    test('cleanTitle strips decorations', () {
      expect(cleanTitle('Blinding Lights (Official Video)'), 'Blinding Lights');
      expect(cleanTitle('Levitating [Official Audio]'), 'Levitating');
      expect(cleanTitle('Stay  feat. Justin Bieber'), 'Stay');
      expect(cleanTitle('Calm Down | Rema'), 'Calm Down');
      expect(cleanTitle('Essence Official Music Video'), 'Essence');
      expect(cleanTitle('No Decorations'), 'No Decorations');
    });

    test('stripBrackets tolerates unmatched', () {
      expect(stripBrackets('a (b) c'), 'a  c');
      expect(stripBrackets('a (b c'), 'a ');
    });

    test('primaryArtist takes the first credit', () {
      expect(primaryArtist('The Weeknd'), 'The Weeknd');
      expect(primaryArtist('Calvin Harris feat. Rihanna'), 'Calvin Harris');
      expect(primaryArtist('Drake, Future & Metro Boomin'), 'Drake');
    });

    test('normalizeArtist drops placeholders and channel decorations', () {
      expect(normalizeArtist('YouTube Music'), '');
      expect(normalizeArtist('Unknown Artist'), '');
      expect(normalizeArtist('<unknown>'), '');
      expect(normalizeArtist('Burna Boy - Topic'), 'Burna Boy');
      expect(normalizeArtist('TheWeekndVEVO'), 'TheWeeknd');
      expect(normalizeArtist('Sauti Sol'), 'Sauti Sol');
    });

    test('splitArtistTitle handles hyphen and dashes', () {
      expect(splitArtistTitle('Daft Punk - Get Lucky'), ('Daft Punk', 'Get Lucky'));
      expect(splitArtistTitle('Daft Punk – Get Lucky'), ('Daft Punk', 'Get Lucky'));
      expect(splitArtistTitle('No Dash Here'), isNull);
      expect(splitArtistTitle('Jay-Z'), isNull);
    });
  });

  group('buildAttempts', () {
    test('original first, then cleaned, then relaxed and title-only', () {
      final a = buildAttempts('Blinding Lights (Official Video)', 'The Weeknd');
      expect(a.first, const LrclibAttempt('Blinding Lights (Official Video)', 'The Weeknd', true));
      expect(a, contains(const LrclibAttempt('Blinding Lights', 'The Weeknd', true)));
      expect(a, contains(const LrclibAttempt('Blinding Lights', 'The Weeknd', false)));
      expect(a.last, const LrclibAttempt('Blinding Lights', '', false));
      expect(a.toSet().length, a.length, reason: 'attempts are deduplicated');
    });

    test('YouTube placeholder artist + "Artist - Title" title is split', () {
      final a = buildAttempts('The Weeknd - Blinding Lights (Official Video)', 'YouTube Music');
      expect(a, contains(const LrclibAttempt('Blinding Lights', 'The Weeknd', true)));
      expect(a.every((x) => x.artist != 'YouTube Music'), isTrue);
    });

    test('empty title yields no attempts', () {
      expect(buildAttempts('   ', 'Someone'), isEmpty);
    });
  });

  group('pickBest', () {
    test('strict mode requires the artist; relaxed mode does not', () {
      final hits = [_hit('Blinding Lights', 'Someone Else')];
      expect(
        pickBest(hits, title: 'Blinding Lights', artist: 'The Weeknd', requireArtist: true),
        isNull,
      );
      expect(
        pickBest(hits, title: 'Blinding Lights', artist: 'The Weeknd', requireArtist: false),
        _synced,
      );
    });

    test('prefers exact artist + close duration + synced', () {
      final hits = [
        _hit('Blinding Lights', 'The Weeknd', duration: 260, synced: null, plain: 'plain'),
        _hit('Blinding Lights', 'The Weeknd', duration: 201),
      ];
      expect(
        pickBest(hits, title: 'Blinding Lights', artist: 'The Weeknd', durationSecs: 200, requireArtist: true),
        _synced,
      );
    });

    test('skips instrumentals and blank lyrics, matches curly quotes', () {
      final hits = [
        _hit('Don\'t Start Now', 'Dua Lipa', instrumental: true),
        _hit('Don\'t Start Now', 'Dua Lipa', synced: '  ', plain: null),
        _hit('Don\'t Start Now', 'Dua Lipa', synced: null, plain: 'Did a full 180'),
      ];
      expect(
        pickBest(hits, title: 'Don’t Start Now', artist: 'Dua Lipa', requireArtist: true),
        'Did a full 180',
      );
    });
  });

  group('LrclibResolver.resolve', () {
    test('exact /api/get hit short-circuits', () async {
      final paths = <String>[];
      final client = MockClient((req) async {
        paths.add(req.url.path);
        expect(req.url.queryParameters['duration'], '200');
        return _json(_hit('Blinding Lights', 'The Weeknd'));
      });
      final text = await LrclibResolver(client: client).resolve(
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        durationMs: 200000,
      );
      expect(text, _synced);
      expect(paths, ['/api/get']);
    });

    test('falls back to cleaned/split search for a messy YouTube track', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/get') {
          final ok = req.url.queryParameters['track_name'] == 'Blinding Lights' &&
              req.url.queryParameters['artist_name'] == 'The Weeknd';
          return ok ? _json(_hit('Blinding Lights', 'The Weeknd')) : _json({'message': 'not found'}, 404);
        }
        return _json(<Object>[]);
      });
      final text = await LrclibResolver(client: client).resolve(
        title: 'The Weeknd - Blinding Lights (Official Video)',
        artist: 'YouTube Music',
      );
      expect(text, _synced);
    });

    test('title-only search finds lyrics when the artist tag is wrong', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/get') return _json({'message': 'nope'}, 404);
        final q = req.url.queryParameters['q'];
        if (q == 'Blinding Lights') return _json([_hit('Blinding Lights', 'The Weeknd')]);
        return _json(<Object>[]);
      });
      final text = await LrclibResolver(client: client).resolve(
        title: 'Blinding Lights',
        artist: 'Track 01 Artist',
      );
      expect(text, _synced);
    });

    test('reuses search results across strict and relaxed attempts', () async {
      final queries = <String>[];
      final client = MockClient((req) async {
        if (req.url.path == '/api/get') return _json({'message': 'nope'}, 404);
        queries.add(req.url.queryParameters['q']!);
        return _json(<Object>[]);
      });
      await LrclibResolver(client: client).resolve(title: 'Song', artist: 'Band');
      expect(queries.toSet().length, queries.length);
    });

    test('gives up after repeated transport failures', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        throw ClientException('offline');
      });
      final text = await LrclibResolver(client: client).resolve(
        title: 'The Weeknd - Blinding Lights (Official Video)',
        artist: 'The Weeknd feat. Someone',
      );
      expect(text, isNull);
      expect(calls, 2);
    });

    test('stops when cancelled', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return _json(<Object>[]);
      });
      final text = await LrclibResolver(client: client).resolve(
        title: 'Song',
        artist: 'Band',
        isCancelled: () => true,
      );
      expect(text, isNull);
      expect(calls, 0);
    });
  });
}
