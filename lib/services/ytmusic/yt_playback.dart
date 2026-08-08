/// Getting YouTube tracks into the player.
///
/// # Why the queue grows instead of being built
///
/// A YouTube track's URL only exists once it has been resolved, one request per
/// track. Resolving a fifty-track playlist before the first note would be five
/// to ten seconds of spinner. So the tapped track is resolved alone, playback
/// starts on it, and the rest arrive behind it — appended to the live queue,
/// never reloaded into it, because reloading would restart the song the user is
/// already listening to.
///
/// # What "play" means here
///
/// Tapping a track plays **from that track to the end of the list**, which is
/// what appending can express without ever disturbing what is already playing.
/// The tracks above it are reachable by "Play all", which starts at the top and
/// therefore queues everything.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../Routes/routes.dart';
import '../../controllers/AppController.dart';
import '../video/video_registry.dart';
import 'parse/yt_json.dart';
import 'yt_models.dart';
import 'yt_repository.dart';

class YtPlayback {
  const YtPlayback._();

  /// How many resolves to have in flight at once while filling the queue.
  ///
  /// Four keeps the queue ahead of playback comfortably without opening a burst
  /// of sockets on a phone radio — which is both slower in practice and the kind
  /// of pattern that earns rate-limiting.
  static const _resolveConcurrency = 4;

  /// Plays [tracks] from [index] onward.
  ///
  /// Returns once playback has started; the rest of the queue fills behind it.
  ///
  /// With [radio] set, the tapped track plays *alone* and an endless station is
  /// built from it instead — what a list of search results wants, where the
  /// items are candidates for one song rather than a running order, and queueing
  /// the other nineteen means following a song with its own remixes, covers and
  /// live versions. Honours the Autoplay preference: with that off the list is
  /// queued as before, because the user has asked the app not to go and find
  /// music by itself, and a queue of the results it already has is not that.
  static Future<void> play(
    BuildContext context,
    List<YtTrack> tracks,
    int index, {
    bool radio = false,
  }) async {
    if (tracks.isEmpty || index < 0 || index >= tracks.length) return;
    final playable = [
      for (final track in tracks.skip(index))
        if (track.isAvailable) track,
    ];
    if (playable.isEmpty) {
      _complain(context, 'Nothing in this list can be played.');
      return;
    }

    final first = playable.first;
    // The cover is fetched next to the resolve, not after it: they are
    // independent requests and waiting for them in turn would show a spinner
    // for the sum of the two.
    final artwork = cacheArtwork(first);
    final target = await _resolveForPlay(context, first);
    if (target == null || !context.mounted) return;
    await artwork;
    if (!context.mounted) return;

    final controller = context.read<AppController>();
    controller.playSongFromList([songModelOf(first, target)], 0);
    Routes.playerTo(context);

    // Attached before the fill starts, not after: `_fillQueue` checks `isLive`
    // to decide whether the queue it is filling still exists, and that check
    // has to be able to see this seed.
    YtRadioQueue.instance.attach(seed: first.videoId);
    if (radio && YtRadioQueue.instance.enabled) {
      // Not `force`: this station is the app's idea, not one the user named, so
      // Autoplay governs it — which the `enabled` check above has already said
      // yes to. Reaching `fill` directly rather than waiting for the queue to
      // run low is the whole point: a queue of one has no "near the end".
      unawaited(YtRadioQueue.instance.fill(controller));
      return;
    }
    // Everything after the first track arrives behind the music.
    _fillQueue(controller, playable.skip(1).toList());
  }

  /// Plays [track] as video.
  ///
  /// # Watching is playing
  ///
  /// A video is not a screen this app navigates to, it is a track it plays. It
  /// enters the queue like any other, on the same player, inside the same
  /// background service — which is what gives it the equaliser, the lock-screen
  /// controls, the queue the user can reach and pick from, and a radio that
  /// takes over when it ends. None of those are video features. They are
  /// consequences of a video being an ordinary member of the queue instead of a
  /// second player standing beside it.
  ///
  /// The player screen is where it appears, because that is where playback
  /// lives.
  ///
  /// # When there is no video to show
  ///
  /// YouTube serves most music videos as separate audio and video streams that
  /// only a DASH manifest can recombine, and iOS cannot open DASH. Rather than
  /// refusing, the track plays as audio and says so — the user asked to hear
  /// this song, and the picture was the part the platform could not provide.
  static Future<void> watch(BuildContext context, YtTrack track) async {
    final artwork = cacheArtwork(track);
    final StreamTarget target;
    try {
      target = await YtMusicRepository.instance
          .videoTarget(track.videoId)
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      if (context.mounted) _complain(context, 'YouTube took too long to answer.');
      return;
    } catch (e) {
      // A dead target is worth forgetting so a retry re-resolves rather than
      // replaying the same expired URL.
      YtMusicRepository.instance.forget(track.videoId);
      if (!context.mounted) return;
      _complain(
        context,
        e is YtException ? e.message : 'That video would not play.',
      );
      return;
    }
    if (!context.mounted) return;

    if (target.format == YtStreamFormat.dash && Platform.isIOS) {
      _complain(
        context,
        'YouTube only offers this one as separate video and audio streams, '
        'which iOS cannot combine. Playing the audio.',
      );
      await play(context, [track], 0);
      return;
    }

    final songId = _songIdOf(track);
    final video = await VideoRegistry.instance.adopt(
      songId: songId,
      videoId: track.videoId,
      target: target,
    );
    if (!context.mounted) return;
    if (video == null) {
      // The manifest could not be staged. The song is still worth playing.
      _complain(context, 'Could not prepare that video. Playing the audio.');
      await play(context, [track], 0);
      return;
    }
    await artwork;
    if (!context.mounted) return;

    final controller = context.read<AppController>();
    controller.playSongFromList([videoModelOf(track)], 0);
    Routes.playerTo(context);

    // Attached before the radio is asked to fill, for the same reason
    // [play] does it in that order: `fill` checks `isLive`, and that check has
    // to be able to see this seed.
    //
    // Unlike a tapped search result this is not gated on Autoplay: a queue of
    // exactly one video has nothing to follow it, and stopping dead after a
    // three-minute video is the behaviour being fixed. The preference governs
    // stations the app invents, and `fill` still honours it.
    YtRadioQueue.instance.attach(seed: track.videoId);
    unawaited(YtRadioQueue.instance.fill(controller));
  }

  /// One video as the player's own model.
  ///
  /// `_data` is the watch URL rather than anything playable: what to open lives
  /// in [VideoRegistry], because a DASH target is a local manifest and a local
  /// path in this field would read as a downloaded file to every part of the app
  /// that inspects it — the artwork layer, the cloud cache, the radio's check
  /// for whether YouTube is still what's playing.
  static SongModel videoModelOf(YtTrack track) => SongModel({
        '_id': _songIdOf(track),
        '_data': 'https://music.youtube.com/watch?v=${track.videoId}',
        'title': track.title,
        'artist': track.artist ?? 'YouTube Music',
        'album': track.thumbnail,
        'duration': ((track.durationSecs ?? 0) * 1000).round(),
        '_display_name': '${track.title}.mp4',
        '_display_name_wo_ext': track.title,
        '_size': 0,
        'file_extension': 'mp4',
        'is_music': true,
      });

  /// Starts a station built from one song — YouTube's "Start radio".
  ///
  /// The seed plays immediately and its related tracks arrive behind it, then
  /// keep arriving for as long as the user listens. This is the *explicit*
  /// version of what [YtRadioQueue] does on its own near the end of a queue,
  /// and unlike that one it is **not gated on the Autoplay preference**: the
  /// setting governs radio the app starts by itself, not radio the user asked
  /// for by name.
  static Future<void> startRadio(BuildContext context, YtTrack seed) async {
    final artwork = cacheArtwork(seed);
    final target = await _resolveForPlay(context, seed);
    if (target == null || !context.mounted) return;
    await artwork;
    if (!context.mounted) return;

    final controller = context.read<AppController>();
    controller.playSongFromList([songModelOf(seed, target)], 0);
    Routes.playerTo(context);

    YtRadioQueue.instance.attach(seed: seed.videoId);
    unawaited(YtRadioQueue.instance.fill(controller, force: true));
  }

  /// Resolves the rest of a list and appends it in order.
  ///
  /// Order is preserved by appending a batch at a time: the requests inside a
  /// batch overlap, but the batches themselves land in sequence, so the queue
  /// never reorders itself while the user is watching it.
  static Future<void> _fillQueue(
    AppController controller,
    List<YtTrack> rest,
  ) async {
    for (var i = 0; i < rest.length; i += _resolveConcurrency) {
      final batch = rest.skip(i).take(_resolveConcurrency).toList();
      final targets = await YtMusicRepository.instance.audioTargets(
        [for (final track in batch) track.videoId],
        concurrency: _resolveConcurrency,
      );
      await Future.wait([for (final track in batch) cacheArtwork(track)]);
      final models = <SongModel>[
        for (final track in batch)
          if (targets[track.videoId] case final target?)
            songModelOf(track, target),
      ];
      // The user may have started something else entirely by now; appending to
      // a queue they've left would graft this playlist onto it.
      if (!YtRadioQueue.instance.isLive) return;
      await controller.appendToQueue(models);
    }

    // Radio normally tops up as the queue advances, but a queue that is already
    // short has no advance to wait for — play one song and nothing would ever
    // ask for more. Asking here covers it, and still honours both the Autoplay
    // preference and the headroom check.
    if (!YtRadioQueue.instance.isLive) return;
    await YtRadioQueue.instance.onIndexChanged(controller, controller.songId);
  }

  /// Puts a track's cover where the app's artwork layer will look for it.
  ///
  /// `ArtworkService.pathFor` handles an `http` track by *reading*
  /// `cloud_art_<id>.png` out of the temp directory — it never fetches. The
  /// fetch lives in `AppController`, and it runs after the player is already
  /// showing the track, by which time `ArtworkWidget` has memoised a future
  /// that resolved to nothing. The result is a cover that stays default for the
  /// whole song.
  ///
  /// Writing the file *before* the track is handed over closes that race: the
  /// widget's first resolve finds it. Failures are silent — a missing cover is
  /// a placeholder, never a reason not to play.
  static Future<void> cacheArtwork(YtTrack track) async {
    final url = track.thumbnail;
    if (url == null || url.isEmpty) return;
    final id = _songIdOf(track);
    try {
      final file = File('${(await getTemporaryDirectory()).path}/cloud_art_$id.png');
      if (file.existsSync() && await file.length() > 0) return;
      // Asked for at a size worth showing full-screen without being the 544 px
      // original for a track that may never be looked at.
      final response = await http.get(Uri.parse(thumbnailAt(url, 512)));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return;
      await file.writeAsBytes(response.bodyBytes);
    } catch (_) {
      // No cover is a placeholder. It is never a reason to fail a play.
    }
  }

  /// The id the player and the artwork layer agree to know this track by.
  static int _songIdOf(YtTrack track) => track.videoId.hashCode.abs();

  /// One track as the player's own model.
  ///
  /// Follows the convention the rest of this app already uses for streamed
  /// tracks: `_data` is the URL to play and the artwork URL rides in `album`,
  /// which is what `loadAudioSource` reads it out of.
  static SongModel songModelOf(YtTrack track, StreamTarget target) => SongModel({
        '_id': _songIdOf(track),
        '_data': target.url,
        'title': track.title,
        'artist': track.artist ?? 'YouTube Music',
        'album': track.thumbnail,
        'duration': ((track.durationSecs ?? 0) * 1000).round(),
        '_display_name': '${track.title}.m4a',
        '_display_name_wo_ext': track.title,
        '_size': 0,
        'file_extension': 'm4a',
        'is_music': true,
      });

  /// Resolves [track] for playback.
  ///
  /// No overlay, no spinner. A prefetched track resolves in zero time and a cold
  /// one in about 250 ms — putting a modal over that makes an instant action
  /// look like a slow one, and the app's loading language is skeletons anyway.
  ///
  /// The resolve is bounded: a request that cannot finish must become an error
  /// the user can act on, never an interface that waits forever.
  static Future<StreamTarget?> _resolveForPlay(
    BuildContext context,
    YtTrack track,
  ) async {
    try {
      return await YtMusicRepository.instance
          .audioTarget(track.videoId)
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      if (context.mounted) _complain(context, 'YouTube took too long to answer.');
      return null;
    } on YtException catch (e) {
      if (context.mounted) _complain(context, e.message);
      return null;
    } catch (e) {
      if (context.mounted) _complain(context, 'Could not play that: $e');
      return null;
    }
  }

  static void _complain(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

/// The endless radio that keeps a YouTube queue from running out.
///
/// Seeded by whatever track started playing, it appends related tracks as the
/// queue nears its end and keeps doing so for as long as the user listens.
///
/// **Automatic fetches are gated on [enabled]** — the same bargain desktop
/// makes. With Autoplay off this class makes no requests of its own accord,
/// rather than fetching a batch and declining to use it.
///
/// The one exception is [fill] with `force`, which is [YtPlayback.startRadio] —
/// a station the user asked for by name. The preference governs what the app
/// decides to do on its own, not what it was told to do.
class YtRadioQueue {
  YtRadioQueue._();

  static final YtRadioQueue instance = YtRadioQueue._();

  static const _prefsKey = 'ytmusic.autoplay';

  /// How close to the end of the queue to get before fetching more. Three
  /// tracks is roughly ten minutes of warning — enough that a slow request
  /// finishes long before the silence it exists to prevent.
  static const _headroom = 3;

  bool _enabled = true;
  String? _seed;
  String? _token;
  bool _fetching = false;

  /// Whether a YouTube queue is the thing currently playing.
  ///
  /// Goes false the moment anything else takes over the player, which is what
  /// stops a half-filled playlist from being grafted onto the local album the
  /// user has since started.
  bool get isLive => _seed != null;

  bool get enabled => _enabled;

  Future<void>? _loading;

  /// Reads the stored Autoplay setting.
  ///
  /// Idempotent, so every screen that depends on the answer can ask on open and
  /// only the first ask touches the disk. That matters because [_enabled] starts
  /// at the default: an unread preference does not read as *unknown*, it reads
  /// as `true`, and a user who turned Autoplay off in an earlier session would
  /// get stations anyway on any screen that hadn't loaded it.
  Future<void> loadPreference() => _loading ??= _read();

  Future<void> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefsKey) ?? true;
    } catch (_) {
      // Unreadable preferences leave the default in place.
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    // The setting is now known first-hand, so a later `loadPreference` must not
    // read the disk back over it — a read still in flight from another screen
    // would otherwise land after this and undo it.
    _loading ??= Future<void>.value();
    if (!value) _token = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {}
  }

  /// Returns the singleton to the state it has at app start.
  @visibleForTesting
  void resetForTest() {
    _loading = null;
    _enabled = true;
    _seed = null;
    _token = null;
    _fetching = false;
  }

  /// Starts watching the queue, seeded by the track that just began.
  void attach({required String seed}) {
    _seed = seed;
    _token = null;
  }

  /// Stops watching. Called when something that isn't YouTube starts playing.
  void detach() {
    _seed = null;
    _token = null;
  }

  /// Called as playback advances. Appends more tracks when the end is near.
  ///
  /// Cheap and safe to call on every index change: it returns immediately
  /// unless a fetch is actually warranted.
  Future<void> onIndexChanged(AppController controller, int index) async {
    if (!_enabled) return;
    final remaining = controller.songs.length - index - 1;
    if (remaining > _headroom) return;
    await fill(controller);
  }

  /// Fetches the next batch of related tracks and appends them.
  ///
  /// [force] is for a radio the user explicitly started, which happens whatever
  /// the Autoplay preference says — that setting is about radio the app decides
  /// to start on its own.
  Future<void> fill(AppController controller, {bool force = false}) async {
    if (_fetching) return;
    if (!_enabled && !force) return;
    final seed = _seed;
    if (seed == null) return;

    _fetching = true;
    try {
      final token = _token;
      final batch = token == null
          ? await YtMusicRepository.instance.radio(seed)
          : await YtMusicRepository.instance.radioContinue(seed, token);

      // A radio that stops offering a token has not necessarily ended; the seed
      // still produces a fresh panel, so forgetting the token re-seeds next time
      // rather than ending the music.
      _token = batch.continuation;
      if (batch.tracks.isEmpty) return;

      final targets = await YtMusicRepository.instance.audioTargets(
        [for (final track in batch.tracks.take(8)) track.videoId],
      );
      await Future.wait(
        [for (final track in batch.tracks.take(8)) YtPlayback.cacheArtwork(track)],
      );
      final models = <SongModel>[
        for (final track in batch.tracks.take(8))
          if (targets[track.videoId] case final target?)
            YtPlayback.songModelOf(track, target),
      ];
      if (models.isEmpty || !isLive) return;
      await controller.appendToQueue(models);
    } catch (_) {
      // Radio is a courtesy. A batch that won't load costs nothing visible —
      // the queue simply ends where it would have anyway.
    } finally {
      _fetching = false;
    }
  }
}

