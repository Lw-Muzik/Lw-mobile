/// What the platform says about the video, as Dart reads it.
///
/// This is a wire format: three fields the native side fills in and the quality
/// menu and the surface both read. Its edges are the interesting part — a
/// missing size before the first frame, a rendition list that changes shape
/// between tracks, an index that no longer refers to anything.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/video.dart';

void main() {
  Map<String, Object?> rendition({
    int width = 1920,
    int height = 1080,
    int bitrate = 4000000,
    double frameRate = 30,
    String codecs = 'avc1.640028',
  }) =>
      {
        'width': width,
        'height': height,
        'bitrate': bitrate,
        'frameRate': frameRate,
        'codecs': codecs,
      };

  group('rendition labels', () {
    test('height is the number people know', () {
      expect(VideoRendition.fromMap(rendition(height: 720)).label, '720p');
    });

    test('a high frame rate is worth saying, an ordinary one is not', () {
      expect(
        VideoRendition.fromMap(rendition(height: 720, frameRate: 60)).label,
        '720p60',
      );
      expect(
        VideoRendition.fromMap(rendition(height: 720, frameRate: 30)).label,
        '720p',
        reason: '720p30 is noise; it is what 720p already means',
      );
    });
  });

  group('video state', () {
    test('an empty state has no video and a usable fallback shape', () {
      const state = VideoState();
      expect(state.hasVideo, isFalse);
      expect(state.aspectRatio, 16 / 9,
          reason: 'a zero-area box collapses the layout and then jumps');
    });

    test('the reported size becomes the aspect ratio', () {
      final state = VideoState.fromMap({
        'width': 1920,
        'height': 1080,
        'pixelAspectRatio': 1.0,
        'renditions': const [],
        'selected': -1,
      });
      expect(state.hasVideo, isTrue);
      expect(state.aspectRatio, closeTo(16 / 9, 0.001));
    });

    test('non-square pixels are accounted for', () {
      final state = VideoState.fromMap({
        'width': 720,
        'height': 480,
        'pixelAspectRatio': 1.333,
        'renditions': const [],
        'selected': -1,
      });
      expect(state.aspectRatio, closeTo(720 * 1.333 / 480, 0.001));
    });

    test('a portrait video is not forced landscape', () {
      final state = VideoState.fromMap({
        'width': 1080,
        'height': 1920,
        'pixelAspectRatio': 1.0,
        'renditions': const [],
        'selected': -1,
      });
      expect(state.aspectRatio, lessThan(1));
    });

    test('missing fields read as absent rather than throwing', () {
      final state = VideoState.fromMap(const {});
      expect(state.hasVideo, isFalse);
      expect(state.renditions, isEmpty);
      expect(state.selectedIndex, -1);
    });

    test('selection defaults to adaptive', () {
      final state = VideoState.fromMap({
        'width': 1920,
        'height': 1080,
        'renditions': [rendition()],
        'selected': -1,
      });
      expect(state.isPinned, isFalse);
      expect(state.selected, isNull,
          reason: 'Auto is the absence of a choice, not a rendition');
    });

    test('a pinned index resolves to its rendition', () {
      final state = VideoState.fromMap({
        'width': 1280,
        'height': 720,
        'renditions': [rendition(height: 1080), rendition(height: 720)],
        'selected': 1,
      });
      expect(state.isPinned, isTrue);
      expect(state.selected?.label, '720p');
    });

    test('an index past the end of the list is not treated as a choice', () {
      final state = VideoState.fromMap({
        'width': 1280,
        'height': 720,
        'renditions': [rendition()],
        'selected': 5,
      });
      expect(state.isPinned, isFalse,
          reason: 'a stale index must not name an arbitrary rendition');
      expect(state.selected, isNull);
    });
  });
}
