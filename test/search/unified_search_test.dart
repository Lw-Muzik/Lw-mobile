/// Searching four places at once, at four different speeds.
///
/// The library answers before the next keystroke; YouTube takes a network
/// round-trip and may never answer at all. The rules that keep that from showing
/// are supersession — a reply for a query the user has moved past is dropped —
/// and silence: a failed YouTube search costs the YouTube section and nothing
/// else, because being offline must not replace someone's own library with an
/// error message.
library;

import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/data/library_database.dart';
import 'package:eq_app/data/library_repository.dart';
import 'package:eq_app/models/cloud_file.dart';
import 'package:eq_app/pages/search/unified_search.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';

YtTrack ytTrack(String id) =>
    YtTrack(videoId: id, title: 'YT $id', playlistId: '', playlistTitle: '');

CloudFile cloudFile(String id, String name) => CloudFile(
      provider: CloudProvider.googleDrive,
      fileId: id,
      name: name,
      folderPath: '/Music',
      size: 1,
      mimeType: 'audio/mpeg',
      trackTitle: name,
      trackArtist: 'Cloud Artist',
    );

void main() {
  late LibraryDatabase db;
  late LibraryRepository repo;

  setUp(() {
    db = LibraryDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
  });

  tearDown(() async => db.close());

  Future<void> insert(int id, String title, {String? artist}) =>
      repo.upsertSongs([
        SongsCompanion.insert(
          id: Value(id),
          data: '/music/$id.mp3',
          title: Value(title),
          artist: Value(artist),
        ),
      ]);

  UnifiedSearch build({
    YouTubeSearch? youtube,
    List<CloudFile>? cloud,
  }) =>
      UnifiedSearch(
        repo: repo,
        loadCloudFiles: () async => cloud ?? const [],
        searchYouTube: youtube ?? (_) async => const [],
        supportsPlaylists: false,
        debounce: const Duration(milliseconds: 1),
      );

  group('local results', () {
    test('a query finds matching library tracks', () async {
      await insert(1, 'Sunrise');
      await insert(2, 'Nightfall');

      final search = build();
      await search.search('sun');

      expect(search.songs.map((s) => s.title), ['Sunrise']);
    });

    test('clearing the query empties everything at once', () async {
      await insert(1, 'Sunrise');
      final search = build();
      await search.search('sun');
      expect(search.songs, isNotEmpty);

      search.onQueryChanged('');
      expect(search.songs, isEmpty);
      expect(search.query, '');
      expect(search.ytLoading, isFalse);
    });
  });

  group('cloud results', () {
    test('matching drive files are found', () async {
      final search = build(cloud: [
        cloudFile('a', 'Sunrise.mp3'),
        cloudFile('b', 'Nightfall.mp3'),
      ]);
      await search.search('sun');
      expect(search.cloudFiles.map((f) => f.name), ['Sunrise.mp3']);
    });

    // A station seeded from a cloud result draws from the whole drive, not
    // from the handful of files that happened to match what was typed.
    test('the whole drive stays available for seeding a station', () async {
      final search = build(cloud: [
        cloudFile('a', 'Sunrise.mp3'),
        cloudFile('b', 'Nightfall.mp3'),
      ]);
      await search.search('sun');
      expect(search.cloudFiles, hasLength(1));
      expect(search.allCloudFiles, hasLength(2));
    });

    test('no drive linked is simply no cloud results', () async {
      final search = build();
      await search.search('sun');
      expect(search.cloudFiles, isEmpty);
    });
  });

  group('YouTube streams in behind the rest', () {
    test('results arrive and the section stops loading', () async {
      final search = build(youtube: (_) async => [ytTrack('v1'), ytTrack('v2')]);
      await search.search('sun');

      expect(search.ytTracks.map((t) => t.videoId), ['v1', 'v2']);
      expect(search.ytLoading, isFalse);
      expect(search.ytFailed, isFalse);
    });

    test('local results are on screen before YouTube answers', () async {
      await insert(1, 'Sunrise');
      final gate = Completer<List<YtTrack>>();
      final search = build(youtube: (_) => gate.future);

      final pending = search.search('sun');
      // Let the local half settle while YouTube is still in the air.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(search.songs.map((s) => s.title), ['Sunrise'],
          reason: 'nothing may wait on the network');
      expect(search.ytLoading, isTrue);

      gate.complete([ytTrack('v1')]);
      await pending;
      expect(search.ytLoading, isFalse);
    });

    // The rule this app is built around: offline is normal.
    test('a failed search is silent and costs only the YouTube section',
        () async {
      await insert(1, 'Sunrise');
      final search =
          build(youtube: (_) async => throw StateError('no network'));

      await search.search('sun');

      expect(search.songs.map((s) => s.title), ['Sunrise'],
          reason: 'the library the user owns is still correct');
      expect(search.ytTracks, isEmpty);
      expect(search.ytFailed, isTrue);
      expect(search.ytLoading, isFalse);
    });

    test('a failure does not leave the section loading for ever', () async {
      final search =
          build(youtube: (_) async => throw StateError('no network'));
      await search.search('sun');
      expect(search.ytLoading, isFalse);
    });
  });

  group('a reply the user has moved past', () {
    test('a superseded YouTube reply is dropped, not rendered', () async {
      final first = Completer<List<YtTrack>>();
      final second = Completer<List<YtTrack>>();
      var call = 0;
      final search = build(youtube: (_) {
        call++;
        return call == 1 ? first.future : second.future;
      });

      final firstRun = search.search('one');
      await Future<void>.delayed(Duration.zero);
      final secondRun = search.search('two');
      await Future<void>.delayed(Duration.zero);

      // The abandoned query answers late.
      first.complete([ytTrack('stale')]);
      await firstRun;

      expect(search.ytTracks, isEmpty,
          reason: 'those are answers to a word no longer on screen');

      second.complete([ytTrack('fresh')]);
      await secondRun;
      expect(search.ytTracks.map((t) => t.videoId), ['fresh']);
    });

    test('a superseded local reply does not overwrite the newer one', () async {
      await insert(1, 'Sunrise');
      await insert(2, 'Nightfall');
      final search = build();

      final stale = search.search('sun');
      final fresh = search.search('night');
      await Future.wait([stale, fresh]);

      expect(search.query, 'night');
      expect(search.songs.map((s) => s.title), ['Nightfall']);
    });

    test('a stale failure does not raise the failed flag on a live query',
        () async {
      final boom = Completer<List<YtTrack>>();
      var call = 0;
      final search = build(youtube: (_) {
        call++;
        return call == 1 ? boom.future : Future.value([ytTrack('ok')]);
      });

      final first = search.search('one');
      await Future<void>.delayed(Duration.zero);
      final second = search.search('two');
      await second;

      boom.completeError(StateError('late failure'));
      await first;

      expect(search.ytFailed, isFalse);
      expect(search.ytTracks.map((t) => t.videoId), ['ok']);
    });
  });

  group('the empty state', () {
    test('does not appear while YouTube is still answering', () async {
      final gate = Completer<List<YtTrack>>();
      final search = build(youtube: (_) => gate.future);

      final pending = search.search('nothing-matches');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(search.isEmptyAndSettled, isFalse,
          reason: 'flashing "no results" before the network answers is a lie');

      gate.complete(const []);
      await pending;
      expect(search.isEmptyAndSettled, isTrue);
    });

    test('appears once everything has answered with nothing', () async {
      final search = build();
      await search.search('nothing-matches');
      expect(search.hasResults, isFalse);
      expect(search.isEmptyAndSettled, isTrue);
    });

    test('one source answering is enough to not be empty', () async {
      final search = build(youtube: (_) async => [ytTrack('v1')]);
      await search.search('nothing-local');
      expect(search.hasResults, isTrue);
    });
  });

  group('typing', () {
    test('is debounced — one search per pause, not one per keystroke',
        () async {
      await insert(1, 'Sunrise');
      var searches = 0;
      final search = build(youtube: (_) async {
        searches++;
        return const [];
      });

      search.onQueryChanged('s');
      search.onQueryChanged('su');
      search.onQueryChanged('sun');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(searches, 1);
      expect(search.query, 'sun');
    });

    test('disposing drops anything still in the air', () async {
      final gate = Completer<List<YtTrack>>();
      final search = build(youtube: (_) => gate.future);
      final pending = search.search('sun');
      await Future<void>.delayed(Duration.zero);

      search.dispose();
      gate.complete([ytTrack('late')]);

      // The assertion is that this completes without notifying a disposed
      // ChangeNotifier, which would throw.
      await expectLater(pending, completes);
    });
  });
}
