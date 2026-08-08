/// Who owns the one video surface, and when it is attached at all.
///
/// There is a single texture and three widgets that may want it, two of which
/// are routinely mounted at once — opening full screen does not unmount the
/// player card beneath it. Get the precedence wrong and the video draws in the
/// place nobody is looking at; get the attach/detach wrong and a phone with its
/// screen off keeps decoding frames and, on a metered connection, paying for
/// them.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/player/video/video_surface.dart';

class _RecordingSink implements VideoSink {
  int attaches = 0;
  int detaches = 0;
  bool attached = false;

  @override
  void attach() {
    attaches++;
    attached = true;
  }

  @override
  void detach() {
    detaches++;
    attached = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final surface = VideoSurface.instance;
  late _RecordingSink sink;

  setUp(() {
    surface.resetForTest();
    sink = _RecordingSink();
    surface.sink = sink;
  });

  tearDown(surface.resetForTest);

  test('nobody claiming means nothing attached', () {
    expect(surface.owner, isNull);
    expect(sink.attached, isFalse);
  });

  test('the first claim attaches the surface', () {
    surface.claim(VideoHost.card);
    expect(surface.owner, VideoHost.card);
    expect(sink.attached, isTrue);
  });

  test('full screen outranks the card mounted beneath it', () {
    surface.claim(VideoHost.card);
    surface.claim(VideoHost.fullscreen);
    expect(surface.owner, VideoHost.fullscreen);
    expect(surface.isOwner(VideoHost.card), isFalse,
        reason: 'the card would be drawing a stream nobody can see');
  });

  test('leaving full screen hands the surface back to the card', () {
    surface.claim(VideoHost.card);
    surface.claim(VideoHost.fullscreen);
    surface.release(VideoHost.fullscreen);
    expect(surface.owner, VideoHost.card);
    expect(sink.attached, isTrue, reason: 'the card is still watching');
  });

  test('the mini player yields to both of the others', () {
    surface.claim(VideoHost.mini);
    expect(surface.owner, VideoHost.mini);
    surface.claim(VideoHost.card);
    expect(surface.owner, VideoHost.card);
    surface.claim(VideoHost.fullscreen);
    expect(surface.owner, VideoHost.fullscreen);
  });

  test('the mini player can tell whether it is needed', () {
    expect(surface.claimedByOther(VideoHost.mini), isFalse);
    surface.claim(VideoHost.card);
    expect(surface.claimedByOther(VideoHost.mini), isTrue,
        reason: 'a floating copy of a video already on screen is clutter');
  });

  test('releasing the last claim detaches', () {
    surface.claim(VideoHost.card);
    surface.release(VideoHost.card);
    expect(surface.owner, isNull);
    expect(sink.attached, isFalse);
  });

  test('a second claim by the same host does not re-attach', () {
    surface.claim(VideoHost.card);
    surface.claim(VideoHost.card);
    expect(sink.attaches, 1);
  });

  test('releasing a host that never claimed changes nothing', () {
    surface.claim(VideoHost.card);
    surface.release(VideoHost.mini);
    expect(surface.owner, VideoHost.card);
    expect(sink.detaches, 0);
  });

  test('backgrounding detaches even though the widgets are still mounted', () {
    surface.claim(VideoHost.card);
    expect(sink.attached, isTrue);

    surface.setForegroundForTest(false);
    expect(surface.owner, isNull, reason: 'nothing is being drawn');
    expect(sink.attached, isFalse,
        reason: 'a screen-off phone should not be decoding video');
  });

  test('returning to the foreground restores the picture', () {
    surface.claim(VideoHost.card);
    surface.setForegroundForTest(false);
    surface.setForegroundForTest(true);
    expect(surface.owner, VideoHost.card);
    expect(sink.attached, isTrue);
  });

  test('backgrounding with nobody watching does not thrash the surface', () {
    surface.setForegroundForTest(false);
    surface.setForegroundForTest(true);
    expect(sink.attaches, 0);
  });

  test('releaseAll clears every host at once', () {
    surface.claim(VideoHost.card);
    surface.claim(VideoHost.fullscreen);
    surface.releaseAll();
    expect(surface.owner, isNull);
    expect(sink.attached, isFalse);
  });

  test('listeners hear about a change of owner', () {
    var notifications = 0;
    void listener() => notifications++;
    surface.addListener(listener);
    addTearDown(() => surface.removeListener(listener));

    surface.claim(VideoHost.card);
    surface.claim(VideoHost.fullscreen);
    surface.release(VideoHost.fullscreen);
    expect(notifications, 3);
  });
}
