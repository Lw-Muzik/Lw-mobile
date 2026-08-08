/// The InnerTube calls behind Discover.
///
/// Five endpoints, no authentication of any kind. That is a deliberate
/// difference from hype-desktop, which browses with a captured cookie jar:
/// measured live against every surface this app uses, YouTube answers all of
/// them signed out — 38 mood categories, five shelves on a genre page, twenty
/// rows per search filter, a playlist's tracks, and a plaintext audio URL. So
/// mobile has no sign-in wall, nothing to expire, and nothing to keep secret.
///
/// # The client identities, and why there are three
///
/// * **WEB_REMIX** — browse, search, suggestions and radio. It is the client YT
///   Music's own web app presents, so its responses are the shapes the parsers
///   in `parse/` were written against.
/// * **ANDROID_VR** — stream resolution. Its URLs are *plaintext* (no signature
///   cipher, no n-parameter JS) **and un-gated**: they serve the whole file.
/// * **IOS** — a fallback for resolution, and the only client that ever offers
///   an `hlsManifestUrl`, which is the sole video path AVPlayer can take.
///
/// # `visitorData` is what makes ANDROID_VR work
///
/// Measured live, ANDROID_VR answered `LOGIN_REQUIRED` — *"Sign in to confirm
/// you're not a bot"* — for six of seven videos. The obvious reading is that the
/// client is burned. It isn't: **the same request with a `visitorData` attached
/// answers `OK` and hands back a plaintext itag 140 url**, even on the older
/// client version. The refusal response itself carries a usable `visitorData` in
/// its `responseContext`, so one is always obtainable — [_visitorData] captures
/// it from every response and [player] retries once after learning one.
///
/// # Why ANDROID_VR leads, and why the order matters more than it looks
///
/// IOS urls are **PO-token prefix-gated: only the first ~1 MiB is ever served**,
/// whatever the Range. That is roughly 64 seconds of itag 140, after which every
/// request 403s — including the sequentially-next chunk. It is invisible to any
/// test that reads a small prefix, which is exactly how it survived a whole
/// round of "verified live" probes here. ANDROID_VR urls have no such wall.
///
/// # What rots
///
/// The client versions below are the thing that ages. When resolution starts
/// failing across the board, refresh them from yt-dlp's `_base_client` entries
/// *before* suspecting anything cleverer — a stale version looks identical to a
/// policy change.
library;

import 'dart:convert';
import 'dart:io';

/// How long any one InnerTube call may take before it is abandoned.
///
/// Generous enough for a slow mobile connection, short enough that a dead
/// network surfaces as an error the user can retry rather than a spinner that
/// never resolves.
const _timeout = Duration(seconds: 20);

const _musicBase = 'https://music.youtube.com/youtubei/v1';
const _playerBase = 'https://youtubei.googleapis.com/youtubei/v1';

const _webRemixVersion = '1.20240403.01.00';
const _webRemixUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

// ---------------------------------------------------------------------------
// THE THING THAT ROTS — the ANDROID_VR identity the `player` call presents.
const _androidVrVersion = '1.65.10';
const _androidVrUserAgent =
    'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; '
    'eureka-user Build/SQ3A.220605.009.A1) gzip';
// ---------------------------------------------------------------------------

const _iosVersion = '20.10.4';
const _iosUserAgent =
    'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X; en_US)';

/// Which client identity a `player` call presents. See this file's header for
/// why there are two and why ANDROID_VR is tried first.
enum YtPlayerClient { ios, androidVr }

/// Raised when a call could not be completed. Carries a message fit to show.
class YtNetworkException implements Exception {
  final String message;
  const YtNetworkException(this.message);
  @override
  String toString() => message;
}

/// A thin InnerTube client.
///
/// Owns its [HttpClient] so that connections — and their TLS handshakes — are
/// pooled across calls. That is why this is a long-lived object living in the
/// worker isolate rather than something constructed per request: a fresh client
/// per tap would pay a full handshake every time.
class YtInnerTube {
  final HttpClient _http;

  YtInnerTube() : _http = HttpClient() {
    _http.connectionTimeout = const Duration(seconds: 10);
    // A small pool: Discover issues one call per interaction, and holding more
    // sockets open than that costs a phone radio for nothing.
    _http.maxConnectionsPerHost = 4;
    _http.autoUncompress = true;
    // The single most valuable line in this file. Measured on one connection:
    //
    //   cold  (TLS handshake) → 0.74 s
    //   reused                → 0.14 s
    //
    // The request itself is ~140 ms; everything else is the handshake. Dart's
    // default idle timeout is **15 seconds**, which is shorter than the time it
    // takes to read a shelf and decide what to tap — so without this, nearly
    // every play would pay a fresh handshake and feel like a five-times-slower
    // app than it is.
    _http.idleTimeout = const Duration(seconds: 90);
  }

  void close() => _http.close(force: true);

  /// A `browse` call — categories, category pages, artists, playlists, albums.
  Future<Map<String, dynamic>> browse({
    String? browseId,
    String? params,
    String? continuation,
  }) {
    // A continuation is addressed by query string, not by body: the body form
    // answers 200 with an empty section list, which reads as "this playlist
    // ended" and silently truncates it.
    final query = continuation == null
        ? ''
        : '&ctoken=${Uri.encodeQueryComponent(continuation)}'
            '&continuation=${Uri.encodeQueryComponent(continuation)}&type=next';
    return _post(
      '$_musicBase/browse?prettyPrint=false$query',
      {
        'context': _webRemixContext,
        'browseId': ?browseId,
        'params': ?params,
      },
      headers: _webRemixHeaders,
    );
  }

  /// A `search` call. [params] is YouTube's opaque filter token, or null for
  /// the unfiltered mix of shelves.
  Future<Map<String, dynamic>> search(String query, {String? params}) => _post(
        '$_musicBase/search?prettyPrint=false',
        {
          'context': _webRemixContext,
          'query': query,
          'params': ?params,
        },
        headers: _webRemixHeaders,
      );

  /// Type-ahead completions.
  Future<Map<String, dynamic>> suggestions(String query) => _post(
        '$_musicBase/music/get_search_suggestions?prettyPrint=false',
        {'context': _webRemixContext, 'input': query},
        headers: _webRemixHeaders,
      );

  /// A `next` call — the endless "up next" YT Music derives from one song.
  ///
  /// The playlist id is `RDAMVM<videoId>` with the **raw** id and no `VL`
  /// prefix: `next` is the opposite of `browse` on this, and prefixing it here
  /// is an empty panel rather than an error.
  Future<Map<String, dynamic>> next(String videoId, {String? continuation}) =>
      _post(
        '$_musicBase/next?prettyPrint=false',
        {
          'context': _webRemixContext,
          'videoId': videoId,
          'playlistId': 'RDAMVM$videoId',
          'isAudioOnly': true,
          'continuation': ?continuation,
        },
        headers: _webRemixHeaders,
      );

  /// A later page of the station, addressed the way [browse] addresses one.
  ///
  /// The token goes in the **query string**, not the body. That is the same
  /// lesson `browse` above carries: the body form answers 200 with an empty
  /// panel, which reads as "the station ended" and quietly stops an endless
  /// queue at its first page.
  ///
  /// The body still carries the seed, because the wire format re-posts the full
  /// request rather than the token alone.
  Future<Map<String, dynamic>> nextContinuation(
    String videoId,
    String continuation,
  ) =>
      _post(
        '$_musicBase/next?prettyPrint=false'
        '&ctoken=${Uri.encodeQueryComponent(continuation)}'
        '&continuation=${Uri.encodeQueryComponent(continuation)}&type=next',
        {
          'context': _webRemixContext,
          'videoId': videoId,
          'playlistId': 'RDAMVM$videoId',
          'isAudioOnly': true,
        },
        headers: _webRemixHeaders,
      );

  /// The `player` call that resolves a video id to streams.
  ///
  /// Retries once when the answer is a refusal and this call had no
  /// `visitorData` to present — because the refusal itself carries one. That is
  /// the whole of what separates "ANDROID_VR is bot-gated" from "ANDROID_VR
  /// works": see this file's header.
  Future<Map<String, dynamic>> player(
    String videoId, {
    YtPlayerClient client = YtPlayerClient.androidVr,
  }) async {
    final hadVisitor = _visitorData != null;
    final response = await _playerOnce(videoId, client);
    final status = response['playabilityStatus'];
    final refused = status is Map && status['status'] != 'OK';
    if (!refused || hadVisitor || _visitorData == null) return response;
    // A visitor id was learned from the refusal we just received. Asking again
    // with it in hand is a different request, not the same one repeated.
    return _playerOnce(videoId, client);
  }

  Future<Map<String, dynamic>> _playerOnce(
    String videoId,
    YtPlayerClient client,
  ) {
    final identity = switch (client) {
      YtPlayerClient.ios => _iosClient,
      YtPlayerClient.androidVr => _androidVrClient,
    };
    final visitor = _visitorData;
    return _post(
      '$_playerBase/player?prettyPrint=false',
      {
        'context': {
          'client': {
            ...identity,
            'visitorData': ?visitor,
          }
        },
        'videoId': videoId,
        'contentCheckOk': true,
        'racyCheckOk': true,
      },
      headers: {
        ...playbackHeaders(client),
        'X-YouTube-Client-Name': switch (client) {
          YtPlayerClient.ios => '5',
          YtPlayerClient.androidVr => '28',
        },
        'X-YouTube-Client-Version': switch (client) {
          YtPlayerClient.ios => _iosVersion,
          YtPlayerClient.androidVr => _androidVrVersion,
        },
        'X-Goog-Visitor-Id': ?visitor,
      },
    );
  }

  /// The visitor id YouTube has issued this session.
  ///
  /// Captured from *any* response — browse, search and refusals all carry one in
  /// `responseContext`. Held for the life of the worker isolate; nothing about
  /// it is worth persisting, since one is always obtainable from the next call.
  String? _visitorData;

  /// Exposed for the live tests, which assert one is actually being learned.
  String? get visitorData => _visitorData;

  /// The headers a URL resolved by [client] should be fetched with.
  ///
  /// googlevideo has been observed serving these targets to a bare request as
  /// well, but it checks the User-Agent against the resolving client when it
  /// chooses to — so sending them costs nothing and removes a way to 403.
  static Map<String, String> playbackHeaders(YtPlayerClient client) =>
      switch (client) {
        YtPlayerClient.ios => const {'User-Agent': _iosUserAgent},
        YtPlayerClient.androidVr => const {'User-Agent': _androidVrUserAgent},
      };

  /// Playback headers for a URL whose resolving client isn't known.
  ///
  /// The audio player receives tracks as plain URLs — the queue model has no
  /// room for the client that produced each one — so it needs one answer.
  /// [YtPlayerClient.ios] is that answer because it resolves nearly everything
  /// (see this file's header), and because googlevideo has been measured
  /// serving these targets to a request with no User-Agent at all: the header
  /// removes a way to fail rather than being the thing that makes it work.
  static const audioPlaybackHeaders = {'User-Agent': _iosUserAgent};

  /// Whether a URL is one this layer resolved off YouTube's CDN.
  ///
  /// The player uses it to decide that a URL must be streamed directly, with
  /// [audioPlaybackHeaders] and no caching: these targets are single-use, state
  /// their own expiry, and 403 without the User-Agent that resolved them.
  static bool isStreamUrl(String url) => url.contains('googlevideo.com');

  // -------------------------------------------------------------------------

  static const _webRemixContext = {
    'client': {
      'clientName': 'WEB_REMIX',
      'clientVersion': _webRemixVersion,
      'hl': 'en',
      'gl': 'US',
    }
  };

  static const _webRemixHeaders = {
    'User-Agent': _webRemixUserAgent,
    'Origin': 'https://music.youtube.com',
    'X-YouTube-Client-Name': '67',
    'X-YouTube-Client-Version': _webRemixVersion,
  };

  static const _androidVrClient = {
    'clientName': 'ANDROID_VR',
    'clientVersion': _androidVrVersion,
    'androidSdkVersion': 32,
    'userAgent': _androidVrUserAgent,
    'deviceMake': 'Oculus',
    'deviceModel': 'Quest 3',
    'osName': 'Android',
    'osVersion': '12L',
    'hl': 'en',
    'gl': 'US',
  };

  static const _iosClient = {
    'clientName': 'IOS',
    'clientVersion': _iosVersion,
    'deviceMake': 'Apple',
    'deviceModel': 'iPhone16,2',
    'osName': 'iPhone',
    'osVersion': '18.3.2.22D82',
    'hl': 'en',
    'gl': 'US',
    'utcOffsetMinutes': 0,
  };

  Future<Map<String, dynamic>> _post(
    String url,
    Map<String, dynamic> body, {
    required Map<String, String> headers,
  }) async {
    try {
      final request = await _http
          .postUrl(Uri.parse(url))
          .timeout(_timeout, onTimeout: () => throw const YtNetworkException(
                'YouTube took too long to answer.',
              ));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
      headers.forEach(request.headers.set);
      request.add(utf8.encode(jsonEncode(body)));

      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) {
        // Drain so the connection returns to the pool instead of being torn
        // down and re-handshaked on the next call.
        await response.drain<void>();
        throw YtNetworkException(
          'YouTube answered ${response.statusCode}.',
        );
      }
      final text = await response.transform(utf8.decoder).join().timeout(
            _timeout,
          );
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return <String, dynamic>{};
      final visitor = decoded['responseContext'];
      if (visitor is Map && visitor['visitorData'] is String) {
        _visitorData = visitor['visitorData'] as String;
      }
      return decoded;
    } on YtNetworkException {
      rethrow;
    } on SocketException {
      throw const YtNetworkException('No connection to YouTube.');
    } on FormatException {
      // A body that isn't JSON is a shape problem, not an outage — and the
      // parsers downstream would read it as "nothing found" anyway.
      throw const YtNetworkException("YouTube's answer couldn't be read.");
    } catch (e) {
      throw YtNetworkException('Could not reach YouTube: $e');
    }
  }
}
