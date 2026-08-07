/// The isolate every YouTube call runs in.
///
/// # Why an isolate at all
///
/// A category page is ~86 KB on the wire and **1.9 MB decompressed** — measured,
/// not estimated. Decoding that much JSON and walking it takes long enough to
/// drop frames if it happens on the UI isolate, and Discover is the first tab on
/// iOS, so that cost would land on the app's opening screen.
///
/// # Why it is long-lived rather than `Isolate.run` per call
///
/// `Isolate.run` spawns and tears down an isolate per call, which means a new
/// [HttpClient] per call, which means a full TLS handshake per call — a few
/// hundred milliseconds of latency added to every tap, on the mobile radio where
/// it costs the most. One isolate that outlives the requests keeps its
/// connection pool warm, and the spawn is paid once.
///
/// Only small parsed models cross the port. The 1.9 MB tree is decoded, walked
/// and discarded inside the isolate — it never exists on the UI side at all.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'parse/yt_dash.dart';
import 'parse/yt_json.dart';
import 'parse/yt_misc.dart';
import 'parse/yt_page.dart';
import 'parse/yt_tracks.dart';
import 'yt_innertube.dart';
import 'yt_models.dart';

/// What the worker can be asked to do.
enum YtOp {
  categories,
  categoryPage,
  search,
  suggestions,
  artistPage,
  trackList,
  radio,
  radioContinue,
  resolveAudio,
  resolveVideo,
}

class _YtRequest {
  final int id;
  final YtOp op;
  final Map<String, Object?> args;
  const _YtRequest(this.id, this.op, this.args);
}

class _YtResponse {
  final int id;
  final Object? value;
  final String? error;
  const _YtResponse(this.id, {this.value, this.error});
}

/// The single worker the app talks to.
///
/// Spawned on first use and kept for the process's life. If it ever dies, the
/// next call respawns it rather than failing forever — a dead worker must be a
/// slow request, not a broken tab.
class YtWorker {
  YtWorker._();

  static final YtWorker instance = YtWorker._();

  SendPort? _outbound;
  Future<void>? _starting;
  ReceivePort? _inbound;
  Isolate? _isolate;
  var _nextId = 0;
  final _pending = <int, Completer<Object?>>{};

  /// Runs one operation in the worker and returns whatever it parsed.
  Future<T> run<T>(YtOp op, [Map<String, Object?> args = const {}]) async {
    await _ensureStarted();
    final port = _outbound;
    if (port == null) {
      throw const YtNetworkException('Could not start the YouTube worker.');
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    port.send(_YtRequest(id, op, args));
    final value = await completer.future;
    return value as T;
  }

  Future<void> _ensureStarted() {
    if (_outbound != null) return Future.value();
    return _starting ??= _start();
  }

  Future<void> _start() async {
    final inbound = ReceivePort();
    final ready = Completer<SendPort>();
    inbound.listen((message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      if (message is _YtResponse) {
        final completer = _pending.remove(message.id);
        if (completer == null || completer.isCompleted) return;
        final error = message.error;
        if (error != null) {
          completer.completeError(YtNetworkException(error));
        } else {
          completer.complete(message.value);
        }
      }
    });

    try {
      _isolate = await Isolate.spawn(
        _workerMain,
        inbound.sendPort,
        // A worker that dies must not take the app with it, and must not leave
        // its callers waiting forever either — hence both handlers below.
        errorsAreFatal: false,
        debugName: 'yt-music',
      );
      _inbound = inbound;
      _outbound = await ready.future.timeout(const Duration(seconds: 10));
    } catch (e) {
      inbound.close();
      _starting = null;
      throw YtNetworkException('Could not start the YouTube worker: $e');
    }
  }

  /// Tears the worker down. Used when Discover is left for good; the next call
  /// simply starts a fresh one.
  void dispose() {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const YtNetworkException('The YouTube worker was shut down.'),
        );
      }
    }
    _pending.clear();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _inbound?.close();
    _inbound = null;
    _outbound = null;
    _starting = null;
  }
}

/// The worker's side: one client, one port, requests served concurrently.
///
/// Requests are *not* awaited in turn — each is handled in its own future — so a
/// slow category page can't hold up the search the user typed after it.
void _workerMain(SendPort outbound) {
  final inbound = ReceivePort();
  outbound.send(inbound.sendPort);
  final api = YtInnerTube();

  inbound.listen((message) {
    if (message is! _YtRequest) return;
    unawaited(() async {
      try {
        final value = await _handle(api, message.op, message.args);
        outbound.send(_YtResponse(message.id, value: value));
      } on YtNetworkException catch (e) {
        outbound.send(_YtResponse(message.id, error: e.message));
      } catch (e) {
        outbound.send(_YtResponse(message.id, error: 'Something went wrong: $e'));
      }
    }());
  });
}

Future<Object?> _handle(
  YtInnerTube api,
  YtOp op,
  Map<String, Object?> args,
) async {
  switch (op) {
    case YtOp.categories:
      final json = await api.browse(browseId: 'FEmusic_moods_and_genres');
      return parseCategories(json);

    case YtOp.categoryPage:
      final json = await api.browse(
        browseId: 'FEmusic_moods_and_genres_category',
        params: args['params'] as String,
      );
      return parsePage(json);

    case YtOp.search:
      final query = (args['query'] as String).trim();
      // Nothing typed is not an error, and asking YouTube about "" would earn a
      // page of results for nothing.
      if (query.isEmpty) return <ExploreShelf>[];
      final json = await api.search(query, params: args['params'] as String?);
      return parsePage(json);

    case YtOp.suggestions:
      final query = (args['query'] as String).trim();
      if (query.isEmpty) return <String>[];
      final json = await api.suggestions(query);
      return parseSuggestions(json);

    case YtOp.artistPage:
      final json = await api.browse(browseId: args['browseId'] as String);
      return parsePage(json);

    case YtOp.trackList:
      return _trackList(
        api,
        id: args['id'] as String,
        kind: TrackListKind.values[args['kind'] as int],
        fallbackTitle: args['title'] as String? ?? '',
      );

    case YtOp.radio:
      final json = await api.next(args['videoId'] as String);
      return parseRadioPage(json);

    case YtOp.radioContinue:
      final json = await api.next(
        args['videoId'] as String,
        continuation: args['token'] as String,
      );
      return parseRadioPage(json);

    case YtOp.resolveAudio:
      return _resolveAudio(api, args['videoId'] as String);

    case YtOp.resolveVideo:
      return _resolveVideo(api, args['videoId'] as String);
  }
}

/// How many continuation pages to follow before giving up on one list.
///
/// At ~100 rows a page this is far past any playlist a phone wants to hold in a
/// queue; it exists so a token that points at itself can't loop forever.
const _pageLimit = 8;

Future<YtTrackList> _trackList(
  YtInnerTube api, {
  required String id,
  required TrackListKind kind,
  required String fallbackTitle,
}) async {
  final first = parseTrackList(
    await api.browse(browseId: id),
    id: id,
    kind: kind,
    fallbackTitle: fallbackTitle,
  );

  final tracks = [...first.tracks];
  var token = first.continuation;
  var pages = 0;
  final seen = <String>{?token};

  while (token != null && pages < _pageLimit) {
    pages++;
    final YtTrackList page;
    try {
      page = parseTrackList(
        await api.browse(continuation: token),
        id: id,
        kind: kind,
        fallbackTitle: first.title,
      );
    } on YtNetworkException {
      // A page that won't load costs its own rows, not the ones already read:
      // a half-loaded playlist still plays.
      break;
    }
    if (page.tracks.isEmpty) break;
    tracks.addAll(page.tracks);
    final next = page.continuation;
    // A token we've already followed means YouTube is pointing at itself.
    if (next == null || !seen.add(next)) break;
    token = next;
  }

  return YtTrackList(
    title: first.title,
    artist: first.artist,
    thumbnail: first.thumbnail,
    tracks: tracks,
  );
}

/// The clients to try, in order.
///
/// ANDROID_VR leads because its urls serve the **whole file**, where an IOS url
/// is gated to its first ~1 MiB — about 64 seconds of audio, after which every
/// request 403s. IOS is kept as a fallback because it still resolves when VR
/// won't, and because it is the only client that offers HLS for video.
///
/// This order was previously the other way round, on a measurement that was
/// real but incomplete: ANDROID_VR *was* refusing six of seven videos — for want
/// of a `visitorData`, which [YtInnerTube] now supplies. See its header.
const _clientOrder = [YtPlayerClient.androidVr, YtPlayerClient.ios];

/// Video resolves in a different order on iOS, and only there.
///
/// AVPlayer cannot play DASH at all, so on iOS the only usable video is an
/// `hlsManifestUrl` — and IOS is the one client that ever offers one. On
/// Android, ANDROID_VR leads as everywhere else: ExoPlayer plays the DASH
/// manifest built from its adaptive renditions, and VR urls carry no gate.
final _videoClientOrder = Platform.isIOS
    ? const [YtPlayerClient.ios, YtPlayerClient.androidVr]
    : _clientOrder;

/// Asks each client in turn until one answers with a usable response.
///
/// A client that is being bot-gated for this particular video says so through
/// `playabilityStatus`, which is an answer about *that client*, not about the
/// video — so it is a reason to ask the next one rather than to give up. The
/// last client's complaint is the one the user sees.
Future<T> _viaAnyClient<T>(
  YtInnerTube api,
  String videoId,
  T Function(Map<String, dynamic> json, YtPlayerClient client) read, {
  List<YtPlayerClient> order = _clientOrder,
}) async {
  Object? lastError;
  for (final client in order) {
    try {
      final json = await api.player(videoId, client: client);
      _checkPlayable(json);
      return read(json, client);
    } catch (e) {
      lastError = e;
    }
  }
  throw lastError is YtNetworkException
      ? lastError
      : YtNetworkException('Could not play that: $lastError');
}

/// The audio stream for a video id: itag 140, the m4a `just_audio` plays.
Future<StreamTarget> _resolveAudio(YtInnerTube api, String videoId) =>
    _viaAnyClient(api, videoId, (json, client) {
      final formats = ptr(json, 'streamingData/adaptiveFormats');
      if (formats is! List) {
        throw const YtNetworkException(
          'YouTube returned no streams for this track.',
        );
      }
      for (final format in formats) {
        if (ptr(format, 'itag') != 140) continue;
        final url = ptrString(format, 'url');
        if (url == null) {
          // itag 140 present but its URL is behind a signature cipher — the
          // client losing its plaintext exemption. Nothing here can decipher
          // it, so say so plainly rather than fail with something that sounds
          // like a network problem.
          throw const YtNetworkException(
            'YouTube is no longer serving this track in a playable form.',
          );
        }
        return StreamTarget(
          url: url,
          headers: YtInnerTube.playbackHeaders(client),
          expiresAt: _expiryOf(url),
        );
      }
      throw const YtNetworkException(
        'No audio stream available for this track.',
      );
    });

/// The video stream.
///
/// Two shapes, in preference order:
///
/// 1. **HLS**, when YouTube offers a `hlsManifestUrl` — one adaptive URL that
///    ExoPlayer and AVPlayer both play. Rare in practice: of seven music videos
///    measured, one had it.
/// 2. **A DASH manifest built here** from the adaptive renditions, which is what
///    the other six need. See [buildDashManifest] for why, and for the iOS
///    limitation it carries.
Future<StreamTarget> _resolveVideo(YtInnerTube api, String videoId) =>
    _viaAnyClient(api, videoId, order: _videoClientOrder, (json, client) {
      final headers = YtInnerTube.playbackHeaders(client);

      final hls = ptrString(json, 'streamingData/hlsManifestUrl');
      if (hls != null) {
        return StreamTarget(
          url: hls,
          headers: headers,
          expiresAt: _expiryOf(hls),
          format: YtStreamFormat.hls,
        );
      }

      final formats = ptr(json, 'streamingData/adaptiveFormats');
      if (formats is! List) {
        throw const YtNetworkException(
          'No video stream available for this track.',
        );
      }

      // AVC in MP4 only: an adaptation set holds one container and codec
      // family, and AVC is the rendition every device decodes in hardware.
      final video = <DashStream>[];
      DashStream? audio;
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
      if (video.isEmpty || audio == null) {
        throw const YtNetworkException(
          'No video stream available for this track.',
        );
      }

      final durationMs = int.tryParse(
            ptrString(json, 'videoDetails/lengthSeconds') ?? '',
          ) ??
          0;
      final manifest = buildDashManifest(
        video: video,
        audio: audio,
        duration: Duration(seconds: durationMs),
      );
      return StreamTarget(
        url: manifest,
        headers: headers,
        // The manifest is only as fresh as the URLs inside it.
        expiresAt: _expiryOf(video.first.url),
        format: YtStreamFormat.dash,
      );
    });

/// Turns YouTube's own refusal into the reason, rather than letting it surface
/// later as an empty format list.
void _checkPlayable(Object? json) {
  final status = ptr(json, 'playabilityStatus/status');
  if (status == null || status == 'OK') return;
  final reason = ptrString(json, 'playabilityStatus/reason');
  throw YtNetworkException(reason ?? "YouTube won't play this track.");
}

/// Reads `expire=` out of a resolved URL.
///
/// Hand-scanned rather than parsed: this is one query parameter on a URL we were
/// just handed, and the point is to learn the deadline the CDN already stated.
/// An unreadable or absent value is null — never a default — because a wrong
/// deadline is worse than no deadline.
int? _expiryOf(String url) {
  final match = RegExp(r'[?&/]expire[=/](\d+)').firstMatch(url);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
