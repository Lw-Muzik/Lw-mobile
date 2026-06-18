import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../controllers/AppController.dart';

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

  HttpServer? _server;
  BonsoirBroadcast? _broadcast;
  SharedPreferences? _prefs;

  String _selfId = '';
  String? _pin;
  String? _ip;
  final Map<String, PairedDesktop> _paired = {};

  bool get running => _server != null;
  String? get pin => _pin;
  int? get port => _server?.port;
  String? get ip => _ip;
  String get deviceName => Platform.isIOS ? 'iPhone' : 'Android phone';
  List<PairedDesktop> get pairedDesktops => _paired.values.toList();

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

    final server = await shelf_io.serve(
      _router().call,
      InternetAddress.anyIPv4,
      0, // ephemeral port — avoids clashes; advertised below.
    );
    server.autoCompress = false; // audio is already compressed.
    _server = server;
    await _advertise(server.port);
    notifyListeners();
  }

  /// Stop serving and withdraw the mDNS advertisement.
  Future<void> stop() async {
    await _broadcast?.stop();
    _broadcast = null;
    await _server?.close(force: true);
    _server = null;
    _pin = null;
    notifyListeners();
  }

  /// Desktops this phone has paired with (loads the store if needed). Used by
  /// the cast controller to authenticate when casting to a discovered desktop.
  Future<List<PairedDesktop>> loadKnownDesktops() async {
    await _ensureLoaded();
    return _paired.values.toList();
  }

  /// Forget a paired desktop (its token stops working).
  Future<void> unpair(String id) async {
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

  Response _handleLibrary(Request request) {
    if (!_authorized(request)) return Response(401, body: 'unauthorized');
    final tracks = AppController.instance.songs.map((s) {
      return {
        'id': s.id.toString(),
        'title': s.title,
        'artist': _clean(s.artist),
        'album': _clean(s.album),
        'durationMs': s.duration,
        'ext': _extOf(s.data),
        'hasArt': false,
      };
    }).toList();
    return _json({'tracks': tracks});
  }

  Future<Response> _handleStream(Request request, String file) async {
    if (!_authorized(request)) return Response(401, body: 'unauthorized');
    final id = file.contains('.')
        ? file.substring(0, file.lastIndexOf('.'))
        : file;
    SongModel? song;
    for (final s in AppController.instance.songs) {
      if (s.id.toString() == id) {
        song = s;
        break;
      }
    }
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

  // ------------------------------------------------------------------ mDNS

  Future<void> _advertise(int port) async {
    final service = BonsoirService(
      name: deviceName,
      type: serviceType,
      port: port,
      attributes: {
        'role': 'source',
        'id': _selfId,
        'name': deviceName,
        'v': '$protocolVersion',
      },
    );
    final broadcast = BonsoirBroadcast(service: service);
    await broadcast.ready;
    await broadcast.start();
    _broadcast = broadcast;
  }

  // --------------------------------------------------------------- helpers

  bool _authorized(Request request) {
    final header = request.headers['authorization'] ?? '';
    if (!header.startsWith('Bearer ')) return false;
    final token = header.substring(7);
    return token.isNotEmpty && _paired.values.any((d) => d.token == token);
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

  String _extOf(String path) {
    final i = path.lastIndexOf('.');
    if (i < 0 || i == path.length - 1) return 'mp3';
    return path.substring(i + 1).toLowerCase();
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
