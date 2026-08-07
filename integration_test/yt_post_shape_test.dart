/// Which part of `YtInnerTube._post` stalls on this device?
///
/// Search (music.youtube.com) works; the player call (youtubei.googleapis.com)
/// hangs. Same method, same client. This varies one thing at a time.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _vrUa = 'com.google.android.apps.youtube.vr.oculus/1.65.10 '
    '(Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip';

const _body = {
  'context': {
    'client': {
      'clientName': 'ANDROID_VR',
      'clientVersion': '1.65.10',
      'androidSdkVersion': 32,
      'userAgent': _vrUa,
      'deviceMake': 'Oculus',
      'deviceModel': 'Quest 3',
      'osName': 'Android',
      'osVersion': '12L',
      'hl': 'en',
      'gl': 'US',
    }
  },
  'videoId': 'Oo4FWZItRG4',
  'contentCheckOk': true,
  'racyCheckOk': true,
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Replicates `_post` with individual knobs turned.
  Future<void> attempt({
    required String label,
    required bool setAcceptEncoding,
    required bool autoUncompress,
    int? maxConnectionsPerHost,
  }) async {
    final watch = Stopwatch()..start();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..autoUncompress = autoUncompress;
    if (maxConnectionsPerHost != null) {
      client.maxConnectionsPerHost = maxConnectionsPerHost;
    }
    try {
      final request = await client.postUrl(Uri.parse(
          'https://youtubei.googleapis.com/youtubei/v1/player?prettyPrint=false'));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      if (setAcceptEncoding) {
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
      }
      request.headers.set('User-Agent', _vrUa);
      request.headers.set('X-YouTube-Client-Name', '28');
      request.headers.set('X-YouTube-Client-Version', '1.65.10');
      request.add(utf8.encode(jsonEncode(_body)));

      final response = await request.close().timeout(const Duration(seconds: 12));
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 12));
      final json = jsonDecode(text) as Map<String, dynamic>;
      // ignore: avoid_print
      print('[shape] $label -> HTTP ${response.statusCode} '
          'enc=${response.headers.value('content-encoding')} '
          'len=${text.length} status=${json['playabilityStatus']?['status']} '
          '(${watch.elapsedMilliseconds}ms)');
    } catch (e) {
      // ignore: avoid_print
      print('[shape] $label -> THREW after ${watch.elapsedMilliseconds}ms: '
          '${e.runtimeType}: $e');
    } finally {
      client.close(force: true);
    }
  }

  testWidgets('vary the post shape', (tester) async {
    await attempt(
        label: 'app shape (Accept-Encoding:gzip + autoUncompress)',
        setAcceptEncoding: true,
        autoUncompress: true);
    await attempt(
        label: 'no Accept-Encoding, autoUncompress on',
        setAcceptEncoding: false,
        autoUncompress: true);
    await attempt(
        label: 'Accept-Encoding:gzip, autoUncompress OFF',
        setAcceptEncoding: true,
        autoUncompress: false);
    await attempt(
        label: 'app shape + maxConnectionsPerHost:4',
        setAcceptEncoding: true,
        autoUncompress: true,
        maxConnectionsPerHost: 4);
  }, timeout: const Timeout(Duration(seconds: 180)));
}
