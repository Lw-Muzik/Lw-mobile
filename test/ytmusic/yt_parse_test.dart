/// The parsers, run against real YouTube responses.
///
/// Every fixture in `test/fixtures/ytmusic/` was captured live and stored
/// gzipped exactly as YouTube sends it — the category page alone is 1.9 MB
/// decompressed, which is also the number that justifies the worker isolate.
///
/// Hand-written JSON would only prove the parsers read what this file imagines
/// YouTube sends. These prove they read what it actually sent.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:eq_app/services/ytmusic/parse/yt_json.dart';
import 'package:eq_app/services/ytmusic/parse/yt_misc.dart';
import 'package:eq_app/services/ytmusic/parse/yt_page.dart';
import 'package:eq_app/services/ytmusic/parse/yt_tracks.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';

Object? fixture(String name) {
  final file = File('test/fixtures/ytmusic/$name.json.gz');
  final bytes = gzip.decode(file.readAsBytesSync());
  return jsonDecode(utf8.decode(bytes));
}

void main() {
  group('categories', () {
    test('reads both grids and every button', () {
      final sections = parseCategories(fixture('categories'));

      expect(sections.map((s) => s.title), ['Moods & moments', 'Genres']);
      expect(sections[0].categories.length, 12);
      expect(sections[1].categories.length, 26);
      expect(sections[0].categories.first.title, 'Chill');
      // The params are what open the category — a category without them is a
      // tile that does nothing, so none may be empty.
      for (final section in sections) {
        for (final category in section.categories) {
          expect(category.params, isNotEmpty, reason: category.title);
          expect(category.title, isNotEmpty);
        }
      }
    });

    test('survives to a round trip through the disk cache', () {
      final sections = parseCategories(fixture('categories'));
      final encoded = jsonEncode([for (final s in sections) s.toJson()]);
      final restored = [
        for (final entry in jsonDecode(encoded) as List)
          ExploreSection.fromJson(entry)!,
      ];
      expect(restored.length, sections.length);
      expect(restored[1].categories.length, 26);
      expect(restored[0].categories.first.params,
          sections[0].categories.first.params);
    });

    test('a shape it understands nothing of is empty, not an error', () {
      expect(parseCategories(null), isEmpty);
      expect(parseCategories('garbage'), isEmpty);
      expect(parseCategories({'contents': {}}), isEmpty);
    });
  });

  group('category page', () {
    late List<ExploreShelf> shelves;

    setUpAll(() => shelves = parsePage(fixture('category_page')));

    test('reads all five shelves the African genre page carries', () {
      expect(
        shelves.map((s) => s.title),
        ['Songs', 'Featured playlists', 'Community playlists', 'Music videos',
          'Albums'],
      );
    });

    /// The bug this whole parser exists for: a "Songs" carousel holds *list
    /// rows*, not cards. A card-only reader silently returns four shelves and
    /// no songs at all.
    test('the Songs carousel yields songs, not nothing', () {
      final songs = shelves.firstWhere((s) => s.title == 'Songs');
      expect(songs.items, hasLength(50));
      expect(songs.items.every((i) => i.kind == ExploreKind.song), isTrue);
      expect(songs.items.every((i) => i.id.isNotEmpty), isTrue);
    });

    test('albums are reachable — the thing upstream could never see', () {
      final albums = shelves.firstWhere((s) => s.title == 'Albums');
      expect(albums.items, hasLength(50));
      expect(albums.items.every((i) => i.kind == ExploreKind.album), isTrue);
      expect(albums.items.every((i) => i.id.startsWith('MPRE')), isTrue);
    });

    test('every playlist id keeps its VL prefix, or the open would 400', () {
      final playlists = shelves
          .expand((s) => s.items)
          .where((i) => i.kind == ExploreKind.playlist);
      expect(playlists, isNotEmpty);
      for (final playlist in playlists) {
        expect(playlist.id, startsWith('VL'), reason: playlist.title);
      }
    });

    test('music videos are classed as video, songs as song', () {
      final videos = shelves.firstWhere((s) => s.title == 'Music videos');
      expect(videos.items.where((i) => i.kind == ExploreKind.video), isNotEmpty);
      expect(videos.items.every((i) => i.hasVideo || !i.isPlayable), isTrue);
    });

    test('no shelf is empty and every item is openable', () {
      expect(shelves, isNotEmpty);
      for (final shelf in shelves) {
        expect(shelf.items, isNotEmpty, reason: shelf.title);
        for (final item in shelf.items) {
          expect(item.id, isNotEmpty);
          expect(item.title, isNotEmpty);
        }
      }
    });
  });

  group('search', () {
    test('a filtered search is one shelf of rows', () {
      final shelves = parsePage(fixture('search_songs'));
      final songs = shelves.firstWhere((s) => s.title == 'Songs');
      expect(songs.items, hasLength(20));
      expect(songs.items.every((i) => i.kind == ExploreKind.song), isTrue);
    });

    /// A search row credits its artist and album by *link*, at columns that move
    /// between surfaces. Reading them by index is what made a play count show up
    /// as an album name.
    test('credits artists and albums by their links', () {
      final songs = parsePage(fixture('search_songs'))
          .firstWhere((s) => s.title == 'Songs');
      final credited = songs.items.where((i) => i.artist != null);
      expect(credited, isNotEmpty);
      for (final item in credited) {
        expect(item.artist, isNot(contains('plays')));
        expect(item.album ?? '', isNot(contains('plays')));
      }
    });

    test('durations are read, and never from a year or a view count', () {
      final songs = parsePage(fixture('search_songs'))
          .firstWhere((s) => s.title == 'Songs');
      final timed = songs.items.where((i) => i.durationSecs != null);
      expect(timed, isNotEmpty);
      // Nothing in a music catalog runs longer than three hours; a four-digit
      // year misread as minutes would land far past it.
      expect(timed.every((i) => i.durationSecs! < 3 * 3600), isTrue);
      expect(timed.every((i) => i.durationSecs! > 0), isTrue);
    });

    test('artist results are pages to open, not tracks to play', () {
      final shelves = parsePage(fixture('search_artists'));
      final artists = shelves.firstWhere((s) => s.title == 'Artists');
      expect(artists.items, isNotEmpty);
      expect(artists.items.every((i) => i.kind == ExploreKind.artist), isTrue);
      expect(artists.items.every((i) => i.id.startsWith('UC')), isTrue);
    });

    test('suggestions arrive joined, not split at the bold', () {
      final suggestions = parseSuggestions(fixture('suggestions'));
      expect(suggestions, contains('burna boy'));
      expect(suggestions.length, greaterThan(1));
      // Split runs would give "burna " and "boy" as separate halves.
      expect(suggestions.every((s) => s.trim() == s), isTrue);
    });

    test('unreadable suggestions are none, never an error', () {
      expect(parseSuggestions(null), isEmpty);
      expect(parseSuggestions({'contents': []}), isEmpty);
    });
  });

  group('track lists', () {
    test('a playlist reads its rows, artist and album', () {
      final list = parseTrackList(
        fixture('playlist'),
        id: 'VLRDCLAK5uy_m7AKVv8wPv_keNJSwWzb77kdOPCwBGTYk',
        kind: TrackListKind.playlist,
      );
      expect(list.title, 'The Hits: 80s & Beyond Nigeria');
      expect(list.tracks, hasLength(68));
      final first = list.tracks.first;
      expect(first.title, 'Water No Get Enemy');
      expect(first.artist, 'Fela Kuti');
      expect(first.album, 'The Best of The Black President');
      expect(first.videoId, isNotEmpty);
      expect(first.durationSecs, greaterThan(0));
    });

    /// The column that means "album" on a playlist means "720K plays" on an
    /// album. Reading it blindly is how a play count becomes an album name.
    test('an album takes its title as the album, not column two', () {
      final list = parseTrackList(
        fixture('album'),
        id: 'MPREb_MKmMXRbMBVr',
        kind: TrackListKind.album,
      );
      expect(list.title, 'Miracles');
      expect(list.artist, contains('A Pass'));
      expect(list.tracks, hasLength(7));
      for (final track in list.tracks) {
        expect(track.album, 'Miracles');
        expect(track.album, isNot(contains('plays')));
        // Album rows carry no art of their own — the cover stands in.
        expect(track.thumbnail, isNotNull);
      }
    });

    test('every track is queueable', () {
      final list = parseTrackList(
        fixture('playlist'),
        id: 'VL123',
        kind: TrackListKind.playlist,
      );
      for (final track in list.tracks) {
        expect(track.videoId, isNotEmpty);
        expect(track.title, isNotEmpty);
        expect(track.playlistId, 'VL123');
      }
    });

    test('a response it cannot read is an empty list, not an error', () {
      final list = parseTrackList(
        {'contents': {}},
        id: 'VL123',
        kind: TrackListKind.playlist,
        fallbackTitle: 'Fallback',
      );
      expect(list.tracks, isEmpty);
      expect(list.title, 'Fallback');
    });
  });

  group('radio', () {
    late RadioBatch batch;

    setUpAll(() => batch = parseRadioPage(fixture('radio')));

    test('reads the panel and its continuation token', () {
      expect(batch.tracks, isNotEmpty);
      expect(batch.continuation, isNotNull);
      expect(batch.continuation, isNotEmpty);
    });

    /// The seed comes back as the first row marked `selected`. Queueing it again
    /// would replay the song the user just started.
    test('skips the selected seed row', () {
      expect(batch.tracks.any((t) => t.videoId == 'ccu2OmcLc-4'), isFalse);
      // 50 rows arrived; the seed is the one that must not survive.
      expect(batch.tracks, hasLength(49));
    });

    test('fills the fields the queue needs', () {
      for (final track in batch.tracks) {
        expect(track.videoId, isNotEmpty);
        expect(track.title, isNotEmpty);
        expect(track.playlistTitle, 'Radio');
      }
      expect(batch.tracks.where((t) => t.durationSecs != null), isNotEmpty);
      expect(batch.tracks.where((t) => t.thumbnail != null), isNotEmpty);
    });

    test('never reads a view count as an album', () {
      for (final track in batch.tracks) {
        expect(track.album ?? '', isNot(contains('views')));
      }
    });

    test('a page with nothing in it is empty, not a throw', () {
      final empty = parseRadioPage({'contents': {}});
      expect(empty.tracks, isEmpty);
      expect(empty.continuation, isNull);
    });
  });

  group('stream resolution shapes', () {
    test('the ANDROID_VR player response carries a plaintext itag 140', () {
      final json = fixture('player_androidvr');
      expect(ptr(json, 'playabilityStatus/status'), 'OK');
      final formats = ptr(json, 'streamingData/adaptiveFormats') as List;
      final audio = formats.firstWhere((f) => ptr(f, 'itag') == 140);
      expect(ptrString(audio, 'url'), isNotNull,
          reason: 'a ciphered url would mean the client lost its exemption');
      expect(ptr(audio, 'signatureCipher'), isNull);
      expect(ptr(audio, 'mimeType'), contains('audio/mp4'));
    });

    test('the resolved url states its own expiry', () {
      final json = fixture('player_androidvr');
      final formats = ptr(json, 'streamingData/adaptiveFormats') as List;
      final url = ptrString(
        formats.firstWhere((f) => ptr(f, 'itag') == 140),
        'url',
      )!;
      expect(RegExp(r'[?&/]expire[=/](\d+)').firstMatch(url), isNotNull);
    });
  });

  group('json readers', () {
    test('joins runs rather than indexing them', () {
      expect(
        joinRuns([
          {'text': 'Album'},
          {'text': ' • '},
          {'text': 'A Pass'},
        ]),
        'Album • A Pass',
      );
      expect(joinRuns(null), isNull);
      expect(joinRuns([]), isNull);
      expect(joinRuns([{'text': '  '}]), isNull);
    });

    test('picks the largest thumbnail and tolerates missing dimensions', () {
      expect(
        bestThumbnail([
          {'url': 'small.jpg', 'width': 60, 'height': 60},
          {'url': 'big.jpg', 'width': 544, 'height': 544},
        ]),
        'big.jpg',
      );
      expect(
        bestThumbnail([
          {'url': 'a.jpg'},
          {'url': 'b.jpg', 'width': 10, 'height': 10},
        ]),
        'b.jpg',
      );
      expect(bestThumbnail(null), isNull);
    });

    /// A four-digit year must never read as thirty-three minutes.
    test('parses durations and refuses bare numbers dressed as one', () {
      expect(parseDuration('3:31'), 211);
      expect(parseDuration('1:02:03'), 3723);
      expect(parseDuration(''), isNull);
      expect(parseDuration(null), isNull);
      expect(parseDuration('149M plays'), isNull);
      expect(parseDuration('1:2:3:4'), isNull);
    });

    test('the VL prefix is added once and never twice', () {
      expect(playlistBrowseId('PLabc'), 'VLPLabc');
      expect(playlistBrowseId('VLPLabc'), 'VLPLabc');
    });

    test('thumbnails are requested at the size they are drawn', () {
      const original =
          'https://lh3.googleusercontent.com/abc=w544-h544-l90-rj';
      expect(thumbnailAt(original, 64), endsWith('=w64-h64-l90-rj'));
      // A shape it doesn't recognise is returned untouched: a slightly
      // oversized image is a cost, a broken one is a bug.
      const ytimg = 'https://i.ytimg.com/vi/abc/hqdefault.jpg';
      expect(thumbnailAt(ytimg, 64), ytimg);
    });

    test('a wrong turn in a pointer is null, never a throw', () {
      expect(ptr(null, 'a/b'), isNull);
      expect(ptr({'a': 1}, 'a/b'), isNull);
      expect(ptr({'a': [1, 2]}, 'a/9'), isNull);
      expect(ptr({'a': [1, 2]}, 'a/1'), 2);
      expect(ptr('scalar', 'a'), isNull);
    });
  });
}
