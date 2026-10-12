import 'package:eq_app/models/track_extras.dart';
import 'package:eq_app/services/connect/connect_protocol.dart';
import 'package:eq_app/services/connect/connect_tracks.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';

const me = '6f1d2c3b-4a59-4e6f-8a7b-9c0d1e2f3a4b';

SongModel model(Map<String, Object?> extra) => SongModel({
      '_id': 1,
      '_data': '/music/1.mp3',
      'title': 'T',
      '_display_name': 'x',
      '_display_name_wo_ext': 'x',
      '_size': 0,
      'is_music': true,
      ...extra,
    });

void main() {
  group('trackRefOf', () {
    test('a YouTube stream is yt; its artwork URL is not reported as album', () {
      final ref = trackRefOf(
        model({
          '_id': 99,
          '_data': 'https://rr1---sn.googlevideo.com/videoplayback?x=1',
          'title': 'Never Gonna Give You Up',
          'artist': 'Rick Astley',
          'album': 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
          'duration': 213000,
          TrackKeys.videoId: 'dQw4w9WgXcQ',
        }),
        deviceId: me,
      );
      expect(ref.toJson(), {
        'src': 'yt',
        'videoId': 'dQw4w9WgXcQ',
        'title': 'Never Gonna Give You Up',
        'artist': 'Rick Astley',
        'album': null,
        'durationMs': 213000,
        'artUrl': 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      });
    });

    test('the placeholder artist of an uncredited YouTube track is null', () {
      final ref = trackRefOf(
        model({
          '_data': 'https://music.youtube.com/watch?v=abc',
          'artist': 'YouTube Music',
          TrackKeys.videoId: 'abc',
          TrackKeys.isVideo: true,
        }),
        deviceId: me,
      );
      expect(ref, isA<YtTrackRef>());
      expect(ref.artist, isNull);
    });

    test('a file on this phone is local, by media-store id, art null', () {
      final ref = trackRefOf(
        model({
          '_id': 18342,
          '_data': '/storage/emulated/0/Music/sura.mp3',
          'title': 'Sura Yako',
          'artist': 'Sauti Sol',
          'album': 'Midnight Train',
          'duration': 201000,
        }),
        deviceId: me,
      );
      expect(ref.toJson(), {
        'src': 'local',
        'deviceId': me,
        'id': '18342',
        'title': 'Sura Yako',
        'artist': 'Sauti Sol',
        'album': 'Midnight Train',
        'durationMs': 201000,
        'artUrl': null,
      });
    });

    test('a drive file is other, and a zero duration is unknown', () {
      final ref = trackRefOf(
        model({
          '_data': 'https://www.googleapis.com/drive/v3/files/abc?alt=media',
          'title': 'Demo',
          'artist': '<unknown>',
          'duration': 0,
        }),
        deviceId: me,
      );
      expect(ref.toJson(), {
        'src': 'other',
        'title': 'Demo',
        'artist': null,
        'album': null,
        'durationMs': null,
        'artUrl': null,
      });
    });
  });

  group('queueUids', () {
    SongModel s(int id) => model({'_id': id});

    test('one uid per entry, from the song, repeats numbered', () {
      expect(
        queueUids([s(7), s(8), s(7), s(9), s(7)]),
        ['q-7', 'q-8', 'q-7-2', 'q-9', 'q-7-3'],
      );
    });

    test('an entry keeps its uid when the queue grows behind it', () {
      final before = queueUids([s(1), s(2), s(3)]);
      final after = queueUids([s(1), s(2), s(3), s(4), s(2)]);
      expect(after.take(3), before);
    });

    test('an entry keeps its uid when the queue is reordered', () {
      final order = [s(1), s(2), s(3)];
      final uids = Map.fromIterables(order.map((x) => x.id), queueUids(order));
      final shuffled = [s(3), s(1), s(2)];
      final reshuffled = queueUids(shuffled);
      for (var i = 0; i < shuffled.length; i++) {
        expect(reshuffled[i], uids[shuffled[i].id]);
      }
    });
  });

  group('catalogue mapping', () {
    test('an ExploreItem becomes an Item with milliseconds', () {
      const explore = ExploreItem(
        id: 'dQw4w9WgXcQ',
        kind: ExploreKind.song,
        title: 'Never Gonna Give You Up',
        subtitle: 'Song • Rick Astley • 3:33',
        thumbnail: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        artist: 'Rick Astley',
        album: 'Whenever You Need Somebody',
        durationSecs: 213,
        hasVideo: true,
      );
      expect(itemOf(explore).toJson(), {
        'kind': 'song',
        'id': 'dQw4w9WgXcQ',
        'title': 'Never Gonna Give You Up',
        'subtitle': 'Song • Rick Astley • 3:33',
        'thumbnail': 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        'artist': 'Rick Astley',
        'album': 'Whenever You Need Somebody',
        'durationMs': 213000,
        'hasVideo': true,
      });
    });

    test('an Item opens as the ExploreItem it came from', () {
      const item = Item(
        kind: ItemKind.album,
        id: 'MPREb_abc123',
        title: 'Whenever You Need Somebody',
        subtitle: 'Album • Rick Astley • 1987',
        thumbnail: null,
        artist: 'Rick Astley',
        album: null,
        durationMs: null,
        hasVideo: false,
      );
      final explore = exploreItemOf(item);
      expect(explore.kind, ExploreKind.album);
      expect(explore.id, 'MPREb_abc123');
      expect(itemOf(explore).toJson(), item.toJson());
    });

    test('a yt ref and a YtTrack convert both ways', () {
      const ref = YtTrackRef(
        videoId: 'kJQP7kiw5Fk',
        title: 'Despacito',
        artist: 'Luis Fonsi',
        album: null,
        durationMs: 229000,
        artUrl: 'https://i.ytimg.com/vi/kJQP7kiw5Fk/hqdefault.jpg',
      );
      final track = ytTrackOf(ref);
      expect(track.durationSecs, 229);
      expect(track.thumbnail, ref.artUrl);
      expect(ytRefOf(track).toJson(), ref.toJson());
    });
  });
}
