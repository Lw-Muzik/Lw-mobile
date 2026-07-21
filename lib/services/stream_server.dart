import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../controllers/AppController.dart';
import 'native_mdns.dart';
import 'native_media_store.dart';

/// Thrown when an upload body outgrows [StreamServerController._maxUploadBytes]
/// mid-stream (a chunked request has no Content-Length to pre-check).
class _UploadTooLarge implements Exception {
  const _UploadTooLarge();
}

/// A desktop we've paired with (it holds a matching bearer token).
class PairedDesktop {
  PairedDesktop({required this.id, required this.name, required this.token});

  final String id;
  final String name;
  final String token;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'token': token};

  factory PairedDesktop.fromJson(Map<String, dynamic> j) => PairedDesktop(
        id: j['id'] as String,
        name: j['name'] as String,
        token: j['token'] as String,
      );
}

/// Phone Link — serves this phone's music library to paired desktops over the
/// LAN and advertises itself via mDNS, so the desktop app can browse and stream
/// it through its DSP chain.
///
/// See `hypemuzik-desktop/docs/superpowers/specs/2026-06-18-phone-link-streaming.md`.
class StreamServerController extends ChangeNotifier {
  StreamServerController._();

  /// App-wide singleton so the server keeps running while the app is open,
  /// even if the user leaves the Stream screen.
  static final StreamServerController instance = StreamServerController._();

  static const String serviceType = '_hypemuzik._tcp';
  static const int protocolVersion = 1;
  static const String _kSelfId = 'link_self_id';
  static const String _kPaired = 'link_paired_desktops';
  // The last port we successfully bound. Re-used on every start so an
  // already-paired desktop reconnects at the same ip:port with no mDNS.
  static const String _kPort = 'link_server_port';
  // Opt-in for `POST /upload`. Defaults to OFF: the bearer token a desktop
  // holds was minted to grant *read* access, so honouring writes with it — on
  // pairings that predate this endpoint, no less — would hand out a capability
  // the user never agreed to. Pairing means "you may listen", not "you may put
  // files on my phone"; the user turns this on deliberately.
  static const String _kAllowUploads = 'link_allow_uploads';

  // Ceiling for a single pushed file: comfortably above a long lossless track,
  // far below anything that could fill a phone by accident or malice.
  static const int _maxUploadBytes = 1024 * 1024 * 1024; // 1 GiB
  // Only what the player and MediaStore actually understand. This is a *write*
  // endpoint, so anything else is refused rather than parked in the library.
  // Kept in step with [_contentType], which maps these to a real MIME type.
  static const Set<String> _uploadableExts = {
    'mp3',
    'm4a',
    'mp4',
    'aac',
    'flac',
    'wav',
    'ogg',
  };

  HttpServer? _server;
  BonsoirBroadcast? _broadcast;
  SharedPreferences? _prefs;
  // Throttles the reload-on-auth-miss (a token minted by the *main* isolate may
  // not yet be in this isolate's in-memory set — see [_authorized]).
  DateTime _lastAuthReload = DateTime.fromMillisecondsSinceEpoch(0);

  String _selfId = '';
  String? _pin;
  String? _ip;
  final Map<String, PairedDesktop> _paired = {};
  // The device's full audio library, queried on demand (NOT the player's
  // in-memory queue, which is empty until the user opens the library).
  List<SongModel> _library = [];

  bool get running => _server != null;
  String? get pin => _pin;
  int? get port => _server?.port;
  String? get ip => _ip;
  String get deviceName => Platform.isIOS ? 'iPhone' : 'Android phone';
  List<PairedDesktop> get pairedDesktops => _paired.values.toList();

  /// A JSON-serialisable snapshot of the runtime state, for relaying from the
  /// foreground-service isolate to the UI isolate (tokens are NOT included).
  Map<String, dynamic> stateSnapshot() => {
        'running': running,
        'pin': _pin,
        'ip': _ip,
        'port': _server?.port,
        'paired':
            _paired.values.map((d) => {'id': d.id, 'name': d.name}).toList(),
      };

  Future<void> _ensureLoaded() async {
    if (_prefs != null) return;
    _prefs = await SharedPreferences.getInstance();
    _selfId = _prefs!.getString(_kSelfId) ?? '';
    if (_selfId.isEmpty) {
      _selfId = _randomHex(16);
      await _prefs!.setString(_kSelfId, _selfId);
    }
    final raw = _prefs!.getString(_kPaired);
    if (raw != null) {
      try {
        for (final j in (jsonDecode(raw) as List)) {
          final d = PairedDesktop.fromJson(Map<String, dynamic>.from(j as Map));
          _paired[d.id] = d;
        }
      } catch (_) {/* ignore corrupt store */}
    }
  }

  /// Start the media server + mDNS advertisement. Idempotent.
  Future<void> start() async {
    if (_server != null) return;
    await _ensureLoaded();
    _pin = _generatePin();
    _ip = await _wifiIpv4();

    final server = await _bind();
    server.autoCompress = false; // audio is already compressed.
    _server = server;
    await _advertise(server.port);
    notifyListeners();
  }

  /// Bind the shelf server, preferring the port we last bound successfully so an
  /// already-paired desktop can reconnect at the same ip:port with no discovery.
  /// Falls back to an ephemeral port if the preferred one is taken, and persists
  /// whatever we end up on.
  Future<HttpServer> _bind() async {
    final prefs = _prefs!;
    final preferred = prefs.getInt(_kPort);
    if (preferred != null && preferred > 0) {
      try {
        return await shelf_io.serve(
            _router().call, InternetAddress.anyIPv4, preferred);
      } catch (_) {/* port taken — fall back to an ephemeral one */}
    }
    final server =
        await shelf_io.serve(_router().call, InternetAddress.anyIPv4, 0);
    await prefs.setInt(_kPort, server.port);
    return server;
  }

  /// Stop serving and withdraw the mDNS advertisement.
  Future<void> stop() async {
    await _broadcast?.stop();
    _broadcast = null;
    if (NativeMdns.supported) {
      try {
        await NativeMdns.unregister();
        await NativeMdns.releaseMulticastLock();
      } catch (_) {/* best effort — the process may be tearing down */}
    }
    await _server?.close(force: true);
    _server = null;
    _pin = null;
    // Drop the library snapshot (~0.5-1KB per song — several MB for large
    // libraries) — it used to stay retained for the app's lifetime after
    // sharing stopped. Re-queried on demand when the server starts again.
    _library = [];
    notifyListeners();
  }

  /// Desktops this phone has paired with (loads the store if needed). Used by
  /// the cast controller to authenticate when casting to a discovered desktop.
  /// Reloads from disk first, since pairings may be written by the sharing
  /// server running in a separate (foreground-service) isolate.
  Future<List<PairedDesktop>> loadKnownDesktops() async {
    await _reloadPaired();
    return _paired.values.toList();
  }

  /// Re-read the pairing store from disk into [_paired]. shared_preferences
  /// caches per isolate, so the sharing server (foreground-service isolate) and
  /// the UI/QR flow (main isolate) only see each other's writes after a reload.
  /// Disk is authoritative: every writer saves after mutating, so a
  /// clear-and-rebuild yields the union of all persisted pairings.
  Future<void> _reloadPaired() async {
    await _ensureLoaded();
    try {
      await _prefs?.reload();
      final raw = _prefs?.getString(_kPaired);
      _paired.clear();
      if (raw != null) {
        for (final j in (jsonDecode(raw) as List)) {
          final d = PairedDesktop.fromJson(Map<String, dynamic>.from(j as Map));
          _paired[d.id] = d;
        }
      }
    } catch (_) {/* keep the in-memory set on a read error */}
  }

  /// Reload pairings from disk and notify. Invoked in the service isolate when
  /// the main isolate signals it has minted a token (QR/iroh pairing), so the
  /// running shelf server authorizes the freshly-paired desktop.
  Future<void> reloadPairings() async {
    await _reloadPaired();
    notifyListeners();
  }

  /// Forget a paired desktop (its token stops working). Reloads first so a
  /// concurrent pairing from the other isolate isn't clobbered.
  Future<void> unpair(String id) async {
    await _reloadPaired();
    _paired.remove(id);
    await _savePaired();
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }

  // ----------------------------------------------------------- HTTP routing

  Router _router() {
    final router = Router();
    router.get('/ping', _handlePing);
    router.post('/pair', _handlePair);
    router.get('/library', _handleLibrary);
    router.get('/stream/<file>', _handleStream);
    router.get('/art/<file>', _handleArt);
    router.get('/lyrics/<file>', _handleLyrics);
    router.post('/upload', _handleUpload);
    return router;
  }

  Response _handlePing(Request request) =>
      _json({'name': deviceName, 'id': _selfId, 'v': protocolVersion});

  Future<Response> _handlePair(Request request) async {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return Response(400, body: 'invalid body');
    }
    final pin = '${data['pin'] ?? ''}';
    if (_pin == null || pin != _pin) {
      return Response(403, body: 'incorrect or expired PIN');
    }
    final deviceId = '${data['deviceId'] ?? _randomHex(8)}';
    final deviceName = '${data['deviceName'] ?? 'Desktop'}';
    final token = _randomHex(32);
    await _reloadPaired(); // don't clobber pairings written by the other isolate
    _paired[deviceId] =
        PairedDesktop(id: deviceId, name: deviceName, token: token);
    await _savePaired();
    notifyListeners();
    return _json({
      'token': token,
      'deviceId': deviceId,
      'deviceName': deviceName,
    });
  }

  /// Register a desktop paired over the **remote** (iroh) link: mint a bearer
  /// token, store it so the desktop's tunneled requests pass `_authorized`, and
  /// return it so the phone can hand it to the desktop during the QR handshake.
  /// Mirrors [_handlePair] but driven by the QR/iroh flow instead of HTTP.
  Future<String> registerDesktop(String id, String name) async {
    await _ensureLoaded();
    await _reloadPaired(); // don't clobber pairings written by the service isolate
    final token = _randomHex(32);
    _paired[id] = PairedDesktop(id: id, name: name, token: token);
    await _savePaired();
    notifyListeners();
    return token;
  }

  Future<Response> _handleLibrary(Request request) async {
    if (!await _authorized(request)) return Response(401, body: 'unauthorized');
    final songs = await _loadLibrary();
    final tracks = songs.map((s) {
      return {
        'id': s.id.toString(),
        'title': s.title,
        'artist': _clean(s.artist),
        'album': _clean(s.album),
        'durationMs': s.duration,
        'ext': _extOf(s.data),
        // The folder the file lives in, so the desktop can browse by folder.
        'folder': _folderName(s.data),
        // Optimistic: the desktop tries /art and falls back to a gradient if
        // the track turns out to have no embedded cover.
        'hasArt': true,
      };
    }).toList();
    return _json({'tracks': tracks});
  }

  /// Query the device's full audio library (cached). Falls back to the cache or
  /// the player's loaded songs if the query yields nothing (e.g. transient
  /// permission hiccup), so `/library` and `/stream` always agree.
  Future<List<SongModel>> _loadLibrary() async {
    try {
      final songs = await OnAudioQuery().querySongs();
      if (songs.isNotEmpty) {
        _library = songs;
        return songs;
      }
    } catch (_) {/* fall through to fallbacks */}
    if (_library.isNotEmpty) return _library;
    final fromPlayer = AppController.instance.songs;
    if (fromPlayer.isNotEmpty) _library = fromPlayer;
    return _library;
  }

  /// Find a song by id in the cached library, loading it first if empty.
  Future<SongModel?> _songById(String id) async {
    if (_library.isEmpty) await _loadLibrary();
    for (final s in _library) {
      if (s.id.toString() == id) return s;
    }
    return null;
  }

  Future<Response> _handleArt(Request request, String file) async {
    if (!await _authorized(request)) return Response(401, body: 'unauthorized');
    final songId = int.tryParse(_trackId(file));
    if (songId == null) return Response.notFound('bad id');
    try {
      final bytes = await OnAudioQuery().queryArtwork(
        songId,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: 512,
      );
      if (bytes == null || bytes.isEmpty) return Response.notFound('no art');
      return Response.ok(
        bytes,
        headers: {
          'Content-Type': 'image/jpeg',
          'Cache-Control': 'max-age=86400',
          'Content-Length': '${bytes.length}',
        },
      );
    } catch (_) {
      return Response.notFound('no art');
    }
  }

  /// Serve a track's lyrics: the `.lrc` file the user keeps next to the audio
  /// (same name), as plain text. The desktop tries this first and falls back to
  /// its online sources when there's no sidecar.
  Future<Response> _handleLyrics(Request request, String file) async {
    if (!await _authorized(request)) return Response(401, body: 'unauthorized');
    final song = await _songById(_trackId(file));
    if (song == null) return Response.notFound('no such track');
    final lrc = await _readLrcSidecar(song.data);
    if (lrc == null) return Response.notFound('no lyrics');
    return Response.ok(
      lrc,
      headers: {
        'Content-Type': 'text/plain; charset=utf-8',
        'Cache-Control': 'max-age=3600',
      },
    );
  }

  /// Read a `.lrc` sidecar sitting next to the audio file (same base name).
  /// Tries a few extension casings since Android storage is case-sensitive.
  Future<String?> _readLrcSidecar(String audioPath) async {
    final dot = audioPath.lastIndexOf('.');
    final base = dot >= 0 ? audioPath.substring(0, dot) : audioPath;
    for (final ext in const ['.lrc', '.LRC', '.Lrc']) {
      try {
        final f = File('$base$ext');
        if (await f.exists()) {
          final text = await f.readAsString();
          if (text.trim().isNotEmpty) return text;
        }
      } catch (_) {/* unreadable — try the next casing */}
    }
    return null;
  }

  Future<Response> _handleStream(Request request, String file) async {
    if (!await _authorized(request)) return Response(401, body: 'unauthorized');
    final song = await _songById(_trackId(file));
    if (song == null) return Response.notFound('no such track');

    final f = File(song.data);
    if (!await f.exists()) return Response.notFound('file is missing');
    final length = await f.length();
    final contentType = _contentType(_extOf(song.data));

    final range = request.headers['range'];
    if (range != null && range.startsWith('bytes=')) {
      final spec = range.substring(6).split('-');
      final start = int.tryParse(spec[0]) ?? 0;
      final end = (spec.length > 1 && spec[1].isNotEmpty)
          ? (int.tryParse(spec[1]) ?? length - 1)
          : length - 1;
      final clampedEnd = end >= length ? length - 1 : end;
      if (start > clampedEnd || start < 0) {
        return Response(416, headers: {'Content-Range': 'bytes */$length'});
      }
      return Response(
        206,
        body: f.openRead(start, clampedEnd + 1),
        headers: {
          'Content-Type': contentType,
          'Accept-Ranges': 'bytes',
          'Content-Range': 'bytes $start-$clampedEnd/$length',
          'Content-Length': '${clampedEnd - start + 1}',
        },
      );
    }

    return Response.ok(
      f.openRead(),
      headers: {
        'Content-Type': contentType,
        'Accept-Ranges': 'bytes',
        'Content-Length': '$length',
      },
    );
  }

  // ---------------------------------------------------------------- uploads

  /// Receive a file pushed by a paired desktop and publish it into this phone's
  /// music library. The desktop percent-encodes the name in `X-File-Name`.
  Future<Response> _handleUpload(Request request) async {
    if (!await _authorized(request)) return Response(401, body: 'unauthorized');
    // The token that got us here only ever meant "this desktop may read the
    // library" — accepting writes is a separate, explicit consent.
    if (!await _uploadsAllowed()) {
      return Response(403, body: 'receiving files is turned off on the phone');
    }

    final name = sanitizeUploadName(request.headers['x-file-name'] ?? '');
    if (name.isEmpty) {
      return Response(400, body: 'missing or unusable X-File-Name');
    }
    // Deliberately not [_extOf], which falls back to mp3 for an extension-less
    // path: a sane default when reading our own library, but not when deciding
    // what a desktop is allowed to write.
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
    if (!_uploadableExts.contains(ext)) {
      return Response(415, body: 'unsupported file type');
    }

    final declared = int.tryParse(request.headers['content-length'] ?? '');
    if (declared != null && declared > _maxUploadBytes) {
      return Response(413, body: 'file is too large');
    }

    final dir = Directory('${(await getTemporaryDirectory()).path}/incoming');
    await dir.create(recursive: true);
    // Stage under a unique prefix so two desktops pushing the same title can't
    // land on top of one another.
    final staged = File('${dir.path}/${_randomHex(8)}_$name');
    final part = File('${staged.path}.part');

    try {
      await _writeUpload(request.read(), part);
      // Only a fully-received body is allowed to stop looking like a partial:
      // a dropped connection leaves the `.part`, which the handlers below bin.
      await part.rename(staged.path);
    } on _UploadTooLarge {
      await _deleteQuietly(part);
      return Response(413, body: 'file is too large');
    } on FileSystemException catch (e) {
      await _deleteQuietly(part);
      // Dart exposes no free-space API; ENOSPC (errno 28) is how a full disk
      // actually reaches us, and the desktop maps 507 to its own message.
      if (e.osError?.errorCode == 28) {
        return Response(507, body: 'not enough space on the phone');
      }
      debugPrint('StreamServer: upload write failed: $e');
      return Response(500, body: 'could not save the file');
    } catch (e) {
      await _deleteQuietly(part);
      debugPrint('StreamServer: upload failed: $e');
      return Response(500, body: 'could not save the file');
    }

    try {
      final published = await _publishUpload(staged, name, ext);
      // The cached snapshot no longer matches the library — drop it so the next
      // /library or /stream re-queries and sees the track we just took.
      _library = [];
      return _json(published);
    } catch (e) {
      debugPrint('StreamServer: publishing upload failed: $e');
      return Response(500, body: 'could not add the file to the library');
    } finally {
      // A no-op when [_publishUpload] moved the file rather than copying it.
      await _deleteQuietly(staged);
    }
  }

  /// Stream the request body to [part], enforcing [_maxUploadBytes] as it goes.
  /// Never buffers the whole body — these are music files, and an album push
  /// would OOM the service isolate.
  Future<void> _writeUpload(Stream<List<int>> body, File part) async {
    final sink = part.openWrite();
    var total = 0;
    try {
      await for (final chunk in body) {
        total += chunk.length;
        if (total > _maxUploadBytes) throw const _UploadTooLarge();
        sink.add(chunk);
      }
    } catch (_) {
      // The original error must win over anything close() reports on the way
      // down; the caller deletes the `.part`.
      try {
        await sink.close();
      } catch (_) {/* already failing */}
      rethrow;
    }
    // On the success path a close() failure is fatal rather than ignorable: it
    // is where buffered bytes (and a full disk) actually surface, and swallowing
    // it would rename a truncated file into the library.
    await sink.flush();
    await sink.close();
  }

  /// Publish a fully-received upload into the phone's music library, returning
  /// the `{path, id}` payload for the response.
  ///
  /// Android goes through MediaStore: a file the app merely writes is invisible
  /// to `OnAudioQuery`, so it would never appear in the library nor be
  /// streamable back to the desktop. Elsewhere (iOS, whose music library is
  /// closed to us) the file lands in the app's own documents directory and
  /// reports no id.
  Future<Map<String, dynamic>> _publishUpload(
      File staged, String name, String ext) async {
    if (NativeMediaStore.supported) {
      final imported = await NativeMediaStore.importAudio(
        sourcePath: staged.path,
        displayName: name,
        mimeType: _contentType(ext),
      );
      if (imported == null) {
        throw const FileSystemException('MediaStore insert failed');
      }
      return {'path': imported['path'], 'id': imported['id']};
    }
    final docs = await getApplicationDocumentsDirectory();
    final dest = Directory('${docs.path}/Music');
    await dest.create(recursive: true);
    final out = await staged.rename(_uniquePath(dest, name));
    return {'path': out.path, 'id': null};
  }

  /// A free path for [name] in [dir], suffixing `(2)`, `(3)`… on collision so a
  /// second push of the same title doesn't overwrite the first. (MediaStore
  /// does this for us on Android; this is for the plain-file fallback.)
  String _uniquePath(Directory dir, String name) {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var candidate = '${dir.path}/$name';
    var n = 2;
    while (File(candidate).existsSync()) {
      candidate = '${dir.path}/$stem ($n)$ext';
      n++;
    }
    return candidate;
  }

  Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {/* best effort — the OS reclaims the cache dir anyway */}
  }

  /// Whether the user has opted in to receiving files from a paired desktop.
  ///
  /// Re-read from disk on every call rather than cached: the toggle is written
  /// by the *main* isolate while this server usually runs in the
  /// foreground-service one (the same split [_authorized] reloads for), and a
  /// stale `true` here would keep accepting writes after the user turned them
  /// off. Unlike [_authorized] this isn't throttled — only an already-authorized
  /// desktop can reach it, and an upload is far too heavy for one prefs read to
  /// matter next to it.
  Future<bool> _uploadsAllowed() async {
    await _ensureLoaded();
    try {
      await _prefs?.reload();
    } catch (_) {/* fall back on whatever this isolate last read */}
    return _prefs?.getBool(_kAllowUploads) ?? false;
  }

  /// Whether receiving files from a paired desktop is enabled (see
  /// [_uploadsAllowed] for why this always hits disk).
  Future<bool> allowUploads() => _uploadsAllowed();

  /// Persist the receive-files opt-in. Written from the main isolate; the
  /// sharing server picks it up on its next upload, which re-reads per request.
  Future<void> setAllowUploads(bool value) async {
    await _ensureLoaded();
    await _prefs!.setBool(_kAllowUploads, value);
    notifyListeners();
  }

  /// Reduce the desktop-supplied `X-File-Name` to a bare, safe filename.
  /// Returns an empty string when nothing usable survives — the caller rejects
  /// the request rather than inventing a name for it.
  @visibleForTesting
  static String sanitizeUploadName(String raw) {
    var name = raw;
    try {
      name = Uri.decodeComponent(raw);
    } catch (_) {/* not valid percent-encoding — sanitize the raw value */}
    // Keep only the last path segment, so `../../evil` and `C:\dir\evil` can't
    // smuggle a traversal (or an absolute path) past the target directory.
    name = name.replaceAll('\\', '/');
    name = name.substring(name.lastIndexOf('/') + 1);
    // Legal in a header, not in a filename — and a NUL would truncate the path
    // at the syscall boundary.
    name = name.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '');
    // Strips `.`/`..` outright, and stops an upload from landing as a hidden
    // dotfile the user can't see in their library.
    name = name.replaceAll(RegExp(r'^[.\s]+'), '').trim();
    if (name.isEmpty) return '';
    return _boundNameLength(name);
  }

  /// Clamp a filename to something every filesystem will take, keeping the
  /// extension (MediaStore and the player both key off it).
  static String _boundNameLength(String name) {
    // ext4/F2FS cap a filename at 255 *bytes*, not characters — a CJK or emoji
    // title blows that long before it looks long. The headroom covers the
    // staging prefix and the `.part` suffix.
    const maxBytes = 180;
    if (utf8.encode(name).length <= maxBytes) return name;
    final dot = name.lastIndexOf('.');
    // Only treat a short trailing run as an extension; a stray dot in a long
    // title isn't one.
    final hasExt = dot > 0 && name.length - dot <= 12;
    final ext = hasExt ? name.substring(dot) : '';
    final stem = _clampToBytes(
      hasExt ? name.substring(0, dot) : name,
      maxBytes - utf8.encode(ext).length,
    );
    return stem.isEmpty ? '' : '$stem$ext';
  }

  /// Truncate [s] to at most [maxBytes] of UTF-8 without splitting a code point.
  static String _clampToBytes(String s, int maxBytes) {
    final out = StringBuffer();
    var used = 0;
    for (final rune in s.runes) {
      final size = utf8.encode(String.fromCharCode(rune)).length;
      if (used + size > maxBytes) break;
      out.writeCharCode(rune);
      used += size;
    }
    return out.toString();
  }

  // ------------------------------------------------------------------ mDNS

  Future<void> _advertise(int port) async {
    final txt = <String, String>{
      'role': 'source',
      'id': _selfId,
      'name': deviceName,
      'v': '$protocolVersion',
      // Advertise our own LAN IP so the desktop connects straight to it
      // instead of re-resolving our `.local` hostname (unreliable on Android).
      if (_ip != null && _ip!.isNotEmpty) 'ip': _ip!,
    };

    // Android: advertise via the native NsdManager (a process-level system
    // call, so it works from the foreground-service isolate where the bonsoir
    // plugin — bound to a secondary FlutterEngine — went silent) and hold a
    // MulticastLock so the phone keeps receiving the desktop's mDNS queries in
    // the background.
    if (NativeMdns.supported) {
      try {
        await NativeMdns.acquireMulticastLock();
        await NativeMdns.register(
          name: deviceName,
          type: serviceType,
          port: port,
          txt: txt,
        );
        return;
      } catch (e) {
        debugPrint('StreamServer: native mDNS failed ($e) — trying bonsoir');
        // Fall through to bonsoir as a best-effort fallback.
      }
    }

    // iOS (and the Android fallback): bonsoir, which advertises correctly on
    // iOS and — on the main isolate — on Android too.
    final service = BonsoirService(
      name: deviceName,
      type: serviceType,
      port: port,
      attributes: txt,
    );
    final broadcast = BonsoirBroadcast(service: service);
    await broadcast.initialize();
    await broadcast.start();
    _broadcast = broadcast;
  }

  // --------------------------------------------------------------- helpers

  Future<bool> _authorized(Request request) async {
    final header = request.headers['authorization'] ?? '';
    if (!header.startsWith('Bearer ')) return false;
    final token = header.substring(7);
    if (token.isEmpty) return false;
    if (_paired.values.any((d) => d.token == token)) return true;
    // Miss: the token may have just been minted by the *main* isolate (QR/iroh
    // pairing writes to shared_preferences from there). Reload once — throttled,
    // so a stream of unauthorized probes can't hammer the disk — then re-check.
    final now = DateTime.now();
    if (now.difference(_lastAuthReload) < const Duration(seconds: 3)) {
      return false;
    }
    _lastAuthReload = now;
    await _reloadPaired();
    return _paired.values.any((d) => d.token == token);
  }

  Future<void> _savePaired() async {
    await _prefs?.setString(
      _kPaired,
      jsonEncode(_paired.values.map((d) => d.toJson()).toList()),
    );
  }

  Response _json(Object data) => Response.ok(
        jsonEncode(data),
        headers: {'Content-Type': 'application/json'},
      );

  /// on_audio_query reports unknown tags with a placeholder; surface null so the
  /// desktop can show its own "Unknown artist" instead.
  String? _clean(String? value) {
    if (value == null) return null;
    final v = value.trim();
    if (v.isEmpty || v == '<unknown>') return null;
    return v;
  }

  /// Strip a trailing `.ext` from a `/stream/<id>.<ext>` path segment.
  String _trackId(String file) =>
      file.contains('.') ? file.substring(0, file.lastIndexOf('.')) : file;

  String _extOf(String path) {
    final i = path.lastIndexOf('.');
    if (i < 0 || i == path.length - 1) return 'mp3';
    return path.substring(i + 1).toLowerCase();
  }

  /// The immediate parent folder name of a file path (so the desktop can group
  /// the phone's music by the folders it came from). Null when undeterminable.
  String? _folderName(String path) {
    final parts =
        path.replaceAll('\\', '/').split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) return null;
    final folder = parts[parts.length - 2];
    return folder.isEmpty ? null : folder;
  }

  String _contentType(String ext) {
    switch (ext) {
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
      case 'mp4':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'flac':
        return 'audio/flac';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      default:
        return 'application/octet-stream';
    }
  }

  String _generatePin() => (Random.secure().nextInt(900000) + 100000).toString();

  String _randomHex(int bytes) {
    final r = Random.secure();
    return List<int>.generate(bytes, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<String?> _wifiIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final ni in interfaces) {
        for (final addr in ni.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {/* fall through */}
    return null;
  }
}
