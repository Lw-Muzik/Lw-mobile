/// What the player's song actions stand on: playlists that know what they
/// hold and say when they change, downloads that are started once and
/// remembered, and the song itself read for where it came from.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'package:eq_app/data/library_database.dart';
import 'package:eq_app/data/library_repository.dart';
import 'package:eq_app/models/track_extras.dart';
import 'package:eq_app/player/actions/motion.dart';
import 'package:eq_app/player/actions/song_actions_sheet.dart';
import 'package:eq_app/services/ytmusic/yt_download.dart';
import 'package:eq_app/services/ytmusic/yt_downloads.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';

void main() {
  late LibraryDatabase db;
  late LibraryRepository repo;

  setUp(() {
    db = LibraryDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
  });

  tearDown(() => db.close());

  group('playlists', () {
    test('which playlists already hold a song, by its source', () async {
      final mix = await repo.createPlaylist('Mix', 1);
      final road = await repo.createPlaylist('Road', 1);
      await repo.addToPlaylist(mix, [
        const PlaylistItem(source: 'youtube', externalId: 'abc', title: 'A'),
        const PlaylistItem(source: 'local', songId: 7, title: 'B'),
      ], 2);
      await repo.addToPlaylist(road, [
        const PlaylistItem(source: 'local', songId: 7, title: 'B'),
      ], 2);

      expect(
        await repo.playlistsHolding(
          const PlaylistItem(source: 'youtube', externalId: 'abc', title: 'A'),
        ),
        {mix},
      );
      expect(
        await repo.playlistsHolding(
          const PlaylistItem(source: 'local', songId: 7, title: 'B'),
        ),
        {mix, road},
      );
      // The same id from another source is another song.
      expect(
        await repo.playlistsHolding(
          const PlaylistItem(source: 'cloud', externalId: 'abc', title: 'A'),
        ),
        isEmpty,
      );
    });

    test('every change moves the revision, so lists refresh', () async {
      final seen = <int>[];
      repo.playlistRevision.addListener(
        () => seen.add(repo.playlistRevision.value),
      );
      final id = await repo.createPlaylist('Mix', 1);
      await repo.addToPlaylist(id, [
        const PlaylistItem(source: 'local', songId: 1, title: 'x'),
      ], 2);
      await repo.renamePlaylist(id, 'Mix 2', 3);
      await repo.deletePlaylist(id);
      expect(seen, [1, 2, 3, 4]);
    });
  });

  group('library lookups', () {
    test('songs by title, ignoring case', () async {
      await repo.upsertSongs([
        SongsCompanion.insert(
          id: const Value(1),
          data: '/m/a.m4a',
          title: const Value('Last Last'),
          artist: const Value('Burna Boy'),
        ),
        SongsCompanion.insert(
          id: const Value(2),
          data: '/m/b.m4a',
          title: const Value('Ye'),
        ),
      ]);
      final found = await repo.songsTitled('last last');
      expect(found.map((s) => s.id), [1]);
    });

    test(
      'meta rows by prefix, wildcards in the prefix taken literally',
      () async {
        await repo.metaSet('art:1', '/a');
        await repo.metaSet('art:2', '/b');
        await repo.metaSet('artist', 'x');
        await repo.metaSet('ytdl:v', '/c');
        expect(await repo.metaWithPrefix('art:'), {
          'art:1': '/a',
          'art:2': '/b',
        });
        expect(await repo.metaWithPrefix('a_t'), isEmpty);
      },
    );
  });

  group('downloads', () {
    late Directory dir;
    late YtDownloadFn original;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('yt_downloads');
      original = YtDownloads.instance.downloader;
      YtDownloads.instance.attachRepository(repo);
    });

    tearDown(() async {
      YtDownloads.instance.downloader = original;
      await dir.delete(recursive: true);
    });

    test(
      'a second request joins the first, and the result is remembered',
      () async {
        final finish = Completer<YtDownloadResult>();
        var started = 0;
        final file = File('${dir.path}/song.m4a')..writeAsStringSync('audio');
        YtDownloads.instance.downloader = (track, {onProgress}) {
          started++;
          onProgress?.call(0.5);
          return finish.future;
        };
        const track = YtTrack(videoId: 'v1', title: 'Song');

        final first = YtDownloads.instance.download(track);
        final second = YtDownloads.instance.download(track);
        expect(started, 1);
        expect(YtDownloads.instance.isRunning('v1'), isTrue);
        expect(YtDownloads.instance.progressOf('v1')?.value, 0.5);

        finish.complete(YtDownloadSaved(file.path, inLibrary: true));
        expect(await first, isA<YtDownloadSaved>());
        expect(await second, isA<YtDownloadSaved>());
        expect(YtDownloads.instance.isRunning('v1'), isFalse);
        expect(
          await YtDownloads.instance.localCopy('v1', title: 'Song'),
          file.path,
        );
      },
    );

    test('a deleted download is not a copy any more', () async {
      final file = File('${dir.path}/gone.m4a')..writeAsStringSync('audio');
      await YtDownloads.instance.remember('v2', file.path);
      file.deleteSync();
      expect(await YtDownloads.instance.localCopy('v2', title: 'Gone'), isNull);
    });

    test(
      'a library song of the same title by the same artist is a copy',
      () async {
        final file = File('${dir.path}/Burna Boy - Last Last.m4a')
          ..writeAsStringSync('audio');
        await repo.upsertSongs([
          SongsCompanion.insert(
            id: const Value(3),
            data: file.path,
            title: const Value('Last Last'),
            artist: const Value('Burna Boy'),
          ),
        ]);
        expect(
          await YtDownloads.instance.localCopy(
            'v3',
            title: 'Last Last',
            artist: 'Burna Boy',
          ),
          file.path,
        );
        // Someone else's song of that name is not.
        expect(
          await YtDownloads.instance.localCopy(
            'v4',
            title: 'Last Last',
            artist: 'Somebody Else',
          ),
          isNull,
        );
      },
    );
  });

  group('the song, read', () {
    SongModel song(Map<String, Object?> extra) => SongModel({
      '_id': 1,
      '_data': '/m/a.mp3',
      'title': 'Wilmer',
      'artist': 'Patoranking',
      'album': 'Wilmer',
      'duration': 191000,
      ...extra,
    });

    test('a file on the phone', () {
      final s = SongSubject(song({}));
      expect(s.isDevice, isTrue);
      expect(s.isYouTube || s.isCloud, isFalse);
      expect(s.album, 'Wilmer');
      expect(s.artist, 'Patoranking');
      expect(s.duration, const Duration(seconds: 191));
    });

    test('a YouTube stream: its art URL is not an album, its filler '
        'artist is no artist', () {
      final s = SongSubject(
        song({
          '_data': 'https://rr1.googlevideo.com/videoplayback?x',
          'album': 'https://lh3.googleusercontent.com/art=w544-h544',
          'artist': 'YouTube Music',
          TrackKeys.videoId: 'efmvnvohSI4',
        }),
      );
      expect(s.isYouTube, isTrue);
      expect(s.videoId, 'efmvnvohSI4');
      expect(s.album, isNull);
      expect(s.artist, isNull);
      expect(s.artworkUrl, contains('googleusercontent'));
      final track = s.ytTrack(null);
      expect(track.videoId, 'efmvnvohSI4');
      expect(track.durationSecs, 191);
    });

    test('a drive file streams over http but is not YouTube', () {
      final s = SongSubject(song({'_data': 'https://drive/file'}));
      expect(s.isCloud, isTrue);
      expect(s.isYouTube, isFalse);
    });

    test('the media library\'s placeholders are unknowns', () {
      final s = SongSubject(
        song({'artist': '<unknown>', 'album': 'Unknown Album'}),
      );
      expect(s.artist, isNull);
      expect(s.album, isNull);
    });
  });

  test('the spring settles exactly on its target after one overshoot', () {
    const spring = SpringCurve(dampingRatio: 0.7);
    expect(spring.transform(0), 0);
    expect(spring.transform(1), 1);
    final samples = [for (var i = 1; i < 100; i++) spring.transform(i / 100)];
    final peak = samples.reduce((a, b) => a > b ? a : b);
    expect(peak, greaterThan(1.0));
    expect(peak, lessThan(1.1));
    expect((samples.last - 1).abs(), lessThan(0.02));
  });
}
