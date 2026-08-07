/// Why does a resolve that works from a laptop hang on the phone?
///
/// Probes the `player` call directly on the device, at the raw HTTP level, so
/// the answer isn't filtered through the worker isolate or the retry ladder.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _vrUa = 'com.google.android.apps.youtube.vr.oculus/1.65.10 '
    '(Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 90);

  /// One raw player POST. Returns a short description of what came back.
  Future<String> playerPost({
    required String label,
    String? visitorData,
    bool vr = true,
  }) async {
    final watch = Stopwatch()..start();
    try {
      final request = await client
          .postUrl(Uri.parse(
              'https://youtubei.googleapis.com/youtubei/v1/player?prettyPrint=false'))
          .timeout(const Duration(seconds: 15));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept-Encoding', 'gzip');
      request.headers.set('User-Agent', vr ? _vrUa : 'com.google.ios.youtube/20.10.4');
      request.headers.set('X-YouTube-Client-Name', vr ? '28' : '5');
      request.headers.set('X-YouTube-Client-Version', vr ? '1.65.10' : '20.10.4');
      if (visitorData != null) {
        request.headers.set('X-Goog-Visitor-Id', visitorData);
      }
      request.add(utf8.encode(jsonEncode({
        'context': {
          'client': {
            if (vr) ...{
              'clientName': 'ANDROID_VR',
              'clientVersion': '1.65.10',
              'androidSdkVersion': 32,
              'userAgent': _vrUa,
              'deviceMake': 'Oculus',
              'deviceModel': 'Quest 3',
              'osName': 'Android',
              'osVersion': '12L',
            } else ...{
              'clientName': 'IOS',
              'clientVersion': '20.10.4',
              'deviceMake': 'Apple',
              'deviceModel': 'iPhone16,2',
              'osName': 'iPhone',
              'osVersion': '18.3.2.22D82',
            },
            'hl': 'en',
            'gl': 'US',
            if (visitorData != null) 'visitorData': visitorData,
          }
        },
        'videoId': 'Oo4FWZItRG4',
        'contentCheckOk': true,
        'racyCheckOk': true,
      })));
      final response = await request.close().timeout(const Duration(seconds: 15));
      final body = await response
          .transform(gzip.decoder)
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
      final json = jsonDecode(body) as Map<String, dynamic>;
      final status = json['playabilityStatus']?['status'];
      final formats =
          (json['streamingData']?['adaptiveFormats'] as List?) ?? const [];
      final has140 =
          formats.any((f) => f['itag'] == 140 && f['url'] != null);
      final visitor = json['responseContext']?['visitorData'];
      final result = 'HTTP ${response.statusCode} status=$status '
          'itag140=$has140 gotVisitor=${visitor != null} '
          '(${watch.elapsedMilliseconds}ms)';
      // ignore: avoid_print
      print('[probe] $label -> $result');
      return result;
    } catch (e) {
      // ignore: avoid_print
      print('[probe] $label -> THREW after ${watch.elapsedMilliseconds}ms: $e');
      return 'threw: $e';
    }
  }

  testWidgets('raw player probes on device', (tester) async {
    await playerPost(label: 'VR, no visitorData');
    await playerPost(label: 'VR, no visitorData (2nd)');
    await playerPost(label: 'IOS, no visitorData', vr: false);
  }, timeout: const Timeout(Duration(seconds: 180)));

  testWidgets('does gzip decoding matter?', (tester) async {
    // The app sets Accept-Encoding: gzip and relies on HttpClient's
    // autoUncompress. This checks the same exchange without asking for gzip at
    // all, to rule the codec in or out as the thing that stalls.
    final watch = Stopwatch()..start();
    try {
      final plain = HttpClient()..autoUncompress = true;
      final request = await plain.postUrl(Uri.parse(
          'https://youtubei.googleapis.com/youtubei/v1/player?prettyPrint=false'));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('User-Agent', _vrUa);
      request.headers.set('X-YouTube-Client-Name', '28');
      request.headers.set('X-YouTube-Client-Version', '1.65.10');
      request.add(utf8.encode(jsonEncode({
        'context': {
          'client': {
            'clientName': 'ANDROID_VR',
            'clientVersion': '1.65.10',
            'androidSdkVersion': 32,
            'userAgent': _vrUa,
            'osName': 'Android',
            'osVersion': '12L',
            'hl': 'en',
            'gl': 'US',
          }
        },
        'videoId': 'Oo4FWZItRG4',
        'contentCheckOk': true,
        'racyCheckOk': true,
      })));
      final response = await request.close().timeout(const Duration(seconds: 15));
      final body =
          await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
      // ignore: avoid_print
      print('[probe] no-gzip-header -> HTTP ${response.statusCode} '
          'len=${body.length} (${watch.elapsedMilliseconds}ms)');
      plain.close(force: true);
    } catch (e) {
      // ignore: avoid_print
      print('[probe] no-gzip-header -> THREW after ${watch.elapsedMilliseconds}ms: $e');
    }
  }, timeout: const Timeout(Duration(seconds: 120)));

  tearDownAll(() => client.close(force: true));
}
