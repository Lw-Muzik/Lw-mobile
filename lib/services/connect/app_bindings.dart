/// Hype Connect's ports, wired to this app.
///
/// The executor and the rpc handler are written against small interfaces
/// ([ConnectPlayer], [ConnectLibrary], [ConnectCatalog]) so they can be tested
/// without an audio engine. This file is the other side of those interfaces:
/// the one place where a remote command becomes a call on `AppController`, the
/// YouTube layer or the library database.
///
/// # Nothing here can reach the screen
///
/// None of these classes holds a `BuildContext`, and every call they make
/// either takes none (`playTracks`, `MixPlayback.play`, `playSongFromList`) or
/// is an engine call. A phone being driven from a laptop never opens its player
/// page, never shows a snack bar and never asks a question.
library;

import 'dart:async';

import 'dart:developer' show Timeline;
import 'dart:io' show Platform;

import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:on_audio_query/on_audio_query.dart';

import 'package:eq_app/controllers/app_controller.dart';
import 'package:eq_app/data/library_repository.dart';
import 'package:eq_app/helpers/audio_visualizer.dart';
import 'package:eq_app/models/lyrics_model.dart';
import 'package:eq_app/services/connect/connect_lyrics.dart';
import 'package:eq_app/services/connect/connect_viz.dart';
import 'package:eq_app/visualizers/beat_frame.dart';
import 'package:eq_app/services/connect/connect_executor.dart';
import 'package:eq_app/services/connect/connect_protocol.dart';
import 'package:eq_app/services/connect/connect_rpc.dart';
import 'package:eq_app/services/connect/connect_state_publisher.dart';
import 'package:eq_app/services/connect/connect_tracks.dart';
import 'package:eq_app/services/mixes/mix_playback.dart';
import 'package:eq_app/services/mixes/mix_track_ref.dart';
import 'package:eq_app/services/radio/library_station.dart';
import 'package:eq_app/services/radio/radio_queue.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';
import 'package:eq_app/services/ytmusic/yt_playback.dart';
import 'package:eq_app/services/ytmusic/yt_repository.dart';

/// [ConnectPlayer] over the app's controller and audio handler.
class AppConnectPlayer implements ConnectPlayer {
  AppConnectPlayer(this._app);

  final AppController _app;

  @override
  bool get available => !_app.isEqMode;

  @override
  bool get hasQueue => _app.songs.isNotEmpty;

  @override
  Future<void> play(PlayPlan plan) async {
    switch (plan) {
      case LocalListPlan():
        await _app.playSongFromList(
          plan.songs,
          plan.index,
          initialPosition: plan.startAt,
        );

      case YtListPlan():
        // `playTracks` reads the Autoplay setting synchronously to decide
        // whether a radio follows; before the preference has loaded it reads
        // its default, so a first command after launch would ignore the user's
        // choice.
        await RadioQueue.instance.loadPreference();
        await YtPlayback.playTracks(
          _app,
          plan.tracks,
          0,
          radio: plan.radio,
          startAt: plan.startAt,
        );

      case MixedListPlan():
        await MixPlayback.play(
          _app,
          _Refs([
            for (final item in plan.items)
              switch (item) {
                LocalPlayable(:final song) => MixTrackRef.local(song),
                YtPlayable(:final track) => MixTrackRef.youtube(track),
              },
          ]),
          // Drive files never arrive in a command: their refs are `other`.
          resolveCloud: (_) async => null,
          startAt: plan.startAt,
        );

      case LocalStationPlan(:final seed):
        final repo = AppController.libraryRepo;
        if (repo == null) {
          await _app.playSongFromList([seed], 0);
        } else {
          await _app.playStation(seed, LibraryStation(repo: repo, seed: seed));
        }
    }
  }

  @override
  Future<void> enqueue(List<Playable> items, EnqueueMode mode) async {
    final songs = await _songsFor(items);
    if (songs.isEmpty) return;
    await (mode == EnqueueMode.next
        ? _app.insertNext(songs)
        : _app.appendToQueue(songs));
  }

  /// Queue entries for [items], in order; a YouTube track that will not
  /// resolve is left out, as a mix leaves it out.
  Future<List<SongModel>> _songsFor(List<Playable> items) async {
    final tracks = [
      for (final item in items)
        if (item is YtPlayable) item.track,
    ];
    final targets = tracks.isEmpty
        ? const <String, StreamTarget>{}
        : await YtMusicRepository.instance.audioTargets([
            for (final track in tracks) track.videoId,
          ]);
    await Future.wait([for (final track in tracks) YtPlayback.cacheArtwork(track)]);
    final songs = <SongModel>[];
    for (final item in items) {
      switch (item) {
        case LocalPlayable(:final song):
          songs.add(song);
        case YtPlayable(:final track):
          final target = targets[track.videoId];
          if (target != null) songs.add(YtPlayback.songModelOf(track, target));
      }
    }
    return songs;
  }

  @override
  Future<void> pause() => _app.handler.pause();

  /// Not awaited: just_audio's `play()` completes when playback *pauses*, so
  /// awaiting it would hold the executor's chain for the length of the song.
  @override
  Future<void> resume() async {
    unawaited(_app.handler.play());
  }

  @override
  Future<void> stop() => _app.handler.stop();

  @override
  Future<void> next() async => _app.next();

  @override
  Future<void> prev() async => _app.prev();

  @override
  Future<void> seek(Duration position) => _app.handler.seek(position);

  @override
  Future<bool> jump(String uid) async {
    final queue = List<SongModel>.of(_app.songs);
    final index = queueUids(queue).indexOf(uid);
    if (index < 0) return false;
    // What tapping the entry in the Now Playing sheet does.
    await _app.playSongFromList(queue, index);
    return true;
  }

  @override
  Future<void> setVolume(double value) =>
      _app.handler.currentTrackPlayer.setVolume(value);

  @override
  Future<void> setShuffle(bool on) => _app.setShuffled(on);

  @override
  Future<void> setRepeat(ConnectRepeat mode) => _app.setLoopMode(switch (mode) {
        ConnectRepeat.off => LoopMode.off,
        ConnectRepeat.all => LoopMode.all,
        ConnectRepeat.one => LoopMode.one,
      });
}

class _Refs implements ResolvedMixSource {
  const _Refs(this.tracks);
  @override
  final List<MixTrackRef> tracks;
}

/// [ConnectLibrary] over the library database.
class RepositoryConnectLibrary implements ConnectLibrary {
  RepositoryConnectLibrary(this._repo);

  /// Read at each call: the repository is created during startup, and a
  /// command is allowed to arrive before it exists.
  final LibraryRepository? Function() _repo;

  LibraryRepository get _ready =>
      _repo() ?? (throw StateError('The library is not open yet'));

  @override
  Future<Map<int, SongModel>> songsByIds(Iterable<int> ids) =>
      _ready.songsWithIds(ids);

  @override
  Future<({int total, List<SongModel> songs})> page({
    required int offset,
    required int limit,
    String? query,
  }) => _ready.songsPage(offset: offset, limit: limit, query: query);
}

/// [ConnectCatalog] over this phone's YouTube Music session.
class YtConnectCatalog implements ConnectCatalog {
  YtConnectCatalog(this._app);

  final AppController _app;

  YtMusicRepository get _yt => YtMusicRepository.instance;

  @override
  bool get available => !_app.isEqMode;

  @override
  Future<List<ExploreShelf>> search(String query, SearchFilter filter) =>
      _yt.search(query, filter);

  @override
  Future<List<String>> suggest(String query) => _yt.suggestions(query);

  @override
  Future<({String title, List<YtTrack> tracks})> open(ExploreItem item) async {
    switch (item.kind) {
      case ExploreKind.album:
      case ExploreKind.playlist:
        final list = await _yt.openList(item);
        return (title: list.title, tracks: list.tracks);
      case ExploreKind.song:
      case ExploreKind.video:
      case ExploreKind.artist:
        return (title: item.title, tracks: await _yt.tracksOf(item));
    }
  }

  @override
  Future<List<ExploreShelf>> artist(String browseId) async =>
      (await _yt.artistPage(browseId)).shelves;
}

/// [ConnectStateSource] over the controller and the audio handler.
///
/// Changes come from two places. `AppController` notifies for queue, shuffle and
/// track changes; the handler's `playbackState` covers play, pause, seeks and
/// buffering. The handler's stream is the one that survives a crossfade swap —
/// it is re-bound to whichever player is active — where listening to one
/// `AudioPlayer` would go quiet at the first swap.
class AppConnectStateSource implements ConnectStateSource {
  AppConnectStateSource(this._app) {
    _app.addListener(_poke);
    _playback = _app.handler.playbackState.listen((_) => _poke());
  }

  final AppController _app;
  late final StreamSubscription<Object?> _playback;
  final _changes = StreamController<void>.broadcast(sync: true);

  void _poke() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  ConnectSnapshot read() {
    final handler = _app.handler;
    final player = handler.currentTrackPlayer;
    final queue = _app.songs;
    final index = _app.songId;
    final hasTrack = index >= 0 && index < queue.length;
    final uids = queueUids(queue);
    final firstUpcoming = hasTrack ? index + 1 : 0;
    return ConnectSnapshot(
      track: hasTrack ? queue[index] : null,
      playing: handler.playbackState.value.playing,
      position: player.position,
      duration: player.duration,
      // While a crossfade runs, each player's volume is a point on a ramp, not
      // what the user set; the publisher repeats the last real value.
      volume: identical(player, handler.player) ? player.volume : null,
      shuffle: _app.isShuffled,
      repeat: switch (handler.loopMode) {
        LoopMode.off => ConnectRepeat.off,
        LoopMode.all => ConnectRepeat.all,
        LoopMode.one => ConnectRepeat.one,
      },
      upcoming: [
        for (var i = firstUpcoming;
            i < queue.length && i < firstUpcoming + PlayerState.maxQueue;
            i++)
          UpcomingSong(uids[i], queue[i]),
      ],
    );
  }

  void dispose() {
    _app.removeListener(_poke);
    unawaited(_playback.cancel());
    unawaited(_changes.close());
  }
}

/// [ConnectLyricsSource] over the player's own lyrics resolver.
///
/// Cache first (the player screen has usually loaded them already) and
/// concurrent lookups for a song are shared, so a controller asking while the
/// player screen is still resolving does not start a second fingerprint.
///
/// A lookup that found nothing is remembered for [missTtl]: the web re-asks
/// every 8 s while it has no lyrics, and without this each ask would repeat a
/// full online search for a song that has none.
class AppConnectLyrics implements ConnectLyricsSource {
  AppConnectLyrics(this._app, {this.missTtl = const Duration(minutes: 2)});

  final AppController _app;
  final Duration missTtl;
  final Map<int, DateTime> _missedAt = {};

  @override
  Future<LyricsData?> lyricsFor(SongModel song) async {
    final missed = _missedAt[song.id];
    if (missed != null && DateTime.now().difference(missed) < missTtl) {
      return null;
    }
    final data = await _app.lyricsService.loadLyrics(song);
    if (data == null) {
      _missedAt[song.id] = DateTime.now();
    } else {
      _missedAt.remove(song.id);
    }
    return data;
  }
}

/// [ConnectVizFeed] over the native analysis stream. Listening turns the
/// native tap on (even in the background); cancelling turns it off again.
class AppConnectVizFeed implements ConnectVizFeed {
  AppConnectVizFeed(this._app);

  final AppController _app;
  AudioVisualizer? _ios;

  @override
  Stream<BeatFrame> get frames {
    StreamSubscription<BeatFrame>? source;
    late final StreamController<BeatFrame> out;
    out = StreamController<BeatFrame>(
      onListen: () {
        // iOS delivers beat frames through the shared method-channel handler,
        // which exists once a visualizer has been constructed.
        if (Platform.isIOS) {
          _ios = Visualizers.audioVisualizer();
        }
        _app.setRemoteVisual(true);
        source = AudioVisualizer.beatFrames.listen(
          out.add,
          onError: (Object _) {},
        );
      },
      onCancel: () async {
        await source?.cancel();
        source = null;
        _ios?.dispose();
        _ios = null;
        _app.setRemoteVisual(false);
      },
    );
    return out.stream;
  }
}

/// `Timeline.now`, the clock native heard-at times are read from.
int timelineNowUs() => Timeline.now;
