/// Which queue entries are videos, and what the player is handed for them.
///
/// Worth testing because both failure modes are quiet. A video the registry
/// forgets loses its picture *and* its radio — `AppController` reads this map to
/// decide whether a YouTube queue is still what is playing, so a miss detaches
/// the station that should follow the video. And a DASH target that reaches the
/// player as a URL instead of a written file fails at open time with an error
/// about the manifest, which points nowhere near this.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:eq_app/services/video/video_registry.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';

/// A temporary directory that is a real directory, so manifest writing is
/// exercised rather than stubbed — the thing being checked is that a file
/// appears where the player will look for it.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  final registry = VideoRegistry.instance;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('hype_video_test');
    PathProviderPlatform.instance = _FakePathProvider(temp.path);
    registry.resetForTest();
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  /// Far enough out that [VideoSource.isFresh] is true.
  int soon() => DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;

  test('a DASH target is written to a file the player can open', () async {
    final source = await registry.adopt(
      songId: 7,
      videoId: 'abc123',
      target: StreamTarget(
        url: '<?xml version="1.0"?><MPD/>',
        headers: const {'User-Agent': 'test'},
        format: YtStreamFormat.dash,
        expiresAt: soon(),
      ),
    );

    expect(source, isNotNull);
    final file = File(source!.location);
    expect(file.existsSync(), isTrue,
        reason: 'a DASH manifest is a document, not a URL');
    expect(file.readAsStringSync(), contains('<MPD/>'));
    expect(file.path, endsWith('.mpd'),
        reason: 'ExoPlayer infers DASH from the extension');
  });

  test('a DASH source reaches the player as a file URI with its headers',
      () async {
    final source = await registry.adopt(
      songId: 7,
      videoId: 'abc123',
      target: StreamTarget(
        url: '<MPD/>',
        headers: const {'User-Agent': 'test'},
        format: YtStreamFormat.dash,
        expiresAt: soon(),
      ),
    );

    final audioSource = source!.toAudioSource();
    expect(audioSource, isA<UriAudioSource>());
    final uri = (audioSource as UriAudioSource).uri;
    expect(uri.scheme, 'file');
    // Load-bearing: the BaseURLs inside the manifest point at googlevideo,
    // which checks every segment request against the client that resolved it.
    expect(audioSource.headers, containsPair('User-Agent', 'test'));
  });

  test('an HLS target is kept as a URL, not written anywhere', () async {
    final source = await registry.adopt(
      songId: 8,
      videoId: 'def456',
      target: StreamTarget(
        url: 'https://manifest.googlevideo.com/api/manifest/hls_variant/x.m3u8',
        headers: const {},
        format: YtStreamFormat.hls,
        expiresAt: soon(),
      ),
    );

    expect(source!.location, startsWith('https://'));
    expect(temp.listSync(), isEmpty, reason: 'nothing needed staging');
  });

  test('registering makes the track read as a video', () async {
    expect(registry.isVideo(7), isFalse);
    await registry.adopt(
      songId: 7,
      videoId: 'abc123',
      target: StreamTarget(
        url: '<MPD/>',
        headers: const {},
        format: YtStreamFormat.dash,
        expiresAt: soon(),
      ),
    );
    expect(registry.isVideo(7), isTrue,
        reason: 'AppController reads this to keep the radio attached');
    expect(registry.isVideo(8), isFalse);
  });

  test('clearing forgets everything', () async {
    await registry.adopt(
      songId: 7,
      videoId: 'abc123',
      target: StreamTarget(
        url: '<MPD/>',
        headers: const {},
        format: YtStreamFormat.dash,
        expiresAt: soon(),
      ),
    );
    registry.clear();
    expect(registry.isVideo(7), isFalse);
    expect(registry.isEmpty, isTrue);
  });

  test('a target with no stated deadline is stale immediately', () {
    const source = VideoSource(
      songId: 1,
      videoId: 'x',
      location: 'https://example.test/x.m3u8',
      format: YtStreamFormat.hls,
      headers: {},
    );
    expect(source.isFresh, isFalse,
        reason: 'guessing a lifetime serves URLs the CDN has stopped honouring');
  });

  test('a deadline about to pass counts as stale', () {
    final source = VideoSource(
      songId: 1,
      videoId: 'x',
      location: 'https://example.test/x.m3u8',
      format: YtStreamFormat.hls,
      headers: const {},
      // Inside the minute of headroom: a URL that expires mid-buffer is a stall
      // the user reads as the app breaking.
      expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 30,
    );
    expect(source.isFresh, isFalse);
  });

  test('the sweep removes manifests from earlier runs', () async {
    await registry.adopt(
      songId: 7,
      videoId: 'abc123',
      target: StreamTarget(
        url: '<MPD/>',
        headers: const {},
        format: YtStreamFormat.dash,
        expiresAt: soon(),
      ),
    );
    final directory = Directory('${temp.path}/hype_video');
    expect(directory.listSync(), isNotEmpty);

    await registry.sweepManifests();
    expect(directory.listSync(), isEmpty,
        reason: 'every manifest from a previous launch is stale by definition');
  });

  test('sweeping when nothing was ever written is not an error', () async {
    await expectLater(registry.sweepManifests(), completes);
  });

  test('one video keeps one manifest, however many times it is adopted',
      () async {
    for (var i = 0; i < 3; i++) {
      await registry.adopt(
        songId: 7,
        videoId: 'abc123',
        target: StreamTarget(
          url: '<MPD>$i</MPD>',
          headers: const {},
          format: YtStreamFormat.dash,
          expiresAt: soon(),
        ),
      );
    }
    final directory = Directory('${temp.path}/hype_video');
    expect(directory.listSync().length, 1,
        reason: 'older manifests no longer play; keeping them only fills disk');
    expect(File('${directory.path}/abc123.mpd').readAsStringSync(),
        contains('<MPD>2</MPD>'));
  });
}
