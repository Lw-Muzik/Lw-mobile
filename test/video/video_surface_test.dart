/// Who owns the one video surface, and when it is attached at all.
///
/// There is a single texture and three widgets that may want it, two of which
/// are routinely mounted at once — opening full screen does not unmount the
/// player card beneath it. Get the precedence wrong and the video draws in the
/// place nobody is looking at; get the attach/detach wrong and a phone with its
/// screen off keeps decoding frames and, on a metered connection, paying for
/// them.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/player/video/picture_in_picture.dart';
import 'package:eq_app/player/video/video_surface.dart';

class _RecordingSink implements VideoSink {
  int attaches = 0;
  int detaches = 0;
  bool attached = false;
  bool awake = false;
  int awakeChanges = 0;

  bool floats = false;

  @override
  void keepAwake(bool on) {
    awake = on;
    awakeChanges++;
  }

  /// The other players' surfaces, of which this one-player fake has none.
  int detachOtherCalls = 0;

  @override
  Future<void> detachOthers() async => detachOtherCalls++;

  @override
  void setFloatOnLeave(bool on) => floats = on;

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

/// A sink that behaves the way the real one does, and fails the way it failed.
///
/// The real sink is not the pure function [_RecordingSink] pretends to be:
/// there are two players, each with its own surface, and every attach and
/// detach is a round trip to the platform. A rebind therefore issues two
/// asynchronous operations over one shared set of surfaces, which is exactly
/// the shape a race hides in. Modelling it — a map that both operations touch,
/// a suspension in the middle of each — is what makes the crossfade bug
/// reproducible in a test rather than only on a phone.
class _TwoPlayerSink implements VideoSink {
  /// The player that is audible now — the handler's `currentTrackPlayer`.
  /// A crossfade moves this to the incoming player before the fade begins.
  String current = 'A';

  /// Whether a picture is wanted on each player, and the texture it has.
  final Map<String, bool> wanted = {};
  final Map<String, int?> textures = {};

  /// The player whose surface is actually drawing, or null for a black screen.
  String? get showing {
    for (final entry in textures.entries) {
      if (entry.value != null) return entry.key;
    }
    return null;
  }

  bool awake = false;
  bool floats = false;

  @override
  void attach() => unawaited(_attach(current));

  Future<void> _attach(String player) async {
    wanted[player] = true;
    final id = await Future(() => 1); // the platform round trip
    // Detached while the attach was in flight: see VideoOutput._bind.
    if (wanted[player] != true) return;
    textures[player] = id;
  }

  /// Exactly what `HypeAudioHandler.detachAllVideo` does: walk the surfaces it
  /// knows about, skipping the audible player's, suspending at each one.
  @override
  Future<void> detachOthers() async {
    for (final player in wanted.keys.toList()) {
      if (player == current) continue;
      wanted[player] = false;
      textures[player] = null;
      await null; // cancelling the event channel subscription
    }
  }

  @override
  void detach() {
    wanted[current] = false;
    textures[current] = null;
  }

  @override
  void keepAwake(bool on) => awake = on;

  @override
  void setFloatOnLeave(bool on) => floats = on;
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

  tearDown(() {
    PictureInPicture.instance.isActive.value = false;
    surface.resetForTest();
  });

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

  test('a picture on screen holds the screen awake', () {
    expect(sink.awake, isFalse);
    surface.claim(VideoHost.card);
    expect(sink.awake, isTrue,
        reason: 'a video watched without touching is what the screen timeout '
            'gets wrong');
    surface.release(VideoHost.card);
    expect(sink.awake, isFalse, reason: 'a song does not need the screen');
  });

  test('handing the surface between hosts does not toggle the screen', () {
    surface.claim(VideoHost.card);
    final changes = sink.awakeChanges;
    surface.claim(VideoHost.fullscreen);
    surface.release(VideoHost.fullscreen);
    expect(sink.awake, isTrue);
    expect(sink.awakeChanges, changes,
        reason: 'the picture never left the screen, so nothing changed');
  });

  test('backgrounding releases the screen', () {
    surface.claim(VideoHost.card);
    surface.setForegroundForTest(false);
    expect(sink.awake, isFalse,
        reason: 'a backgrounded app must not pin the screen on');
    surface.setForegroundForTest(true);
    expect(sink.awake, isTrue);
  });

  test('a video on screen asks to keep floating when the app is left', () {
    expect(sink.floats, isFalse);
    surface.claim(VideoHost.card);
    expect(sink.floats, isTrue,
        reason: 'Android refuses the request once the app is already leaving, '
            'so intent has to be registered while the video is still showing');
    surface.release(VideoHost.card);
    expect(sink.floats, isFalse);
  });

  test('the floating window outranks every other host', () {
    surface.claim(VideoHost.card);
    surface.claim(VideoHost.fullscreen);
    surface.claim(VideoHost.pip);
    expect(surface.owner, VideoHost.pip,
        reason: 'the whole app is a thumbnail; only the video belongs in it');
  });

  test('a floating window survives the app being backgrounded', () {
    surface.claim(VideoHost.card);
    PictureInPicture.instance.isActive.value = true;
    surface.setForegroundForTest(false);
    expect(surface.owner, VideoHost.card,
        reason: 'picture-in-picture backgrounds the app while the video is '
            'still on screen; tearing the surface down blacks it out');
    expect(sink.attached, isTrue);
  });

  test('leaving the floating window while backgrounded does detach', () {
    surface.claim(VideoHost.card);
    PictureInPicture.instance.isActive.value = true;
    surface.setForegroundForTest(false);
    PictureInPicture.instance.isActive.value = false;
    expect(surface.owner, isNull);
    expect(sink.attached, isFalse);
  });

  group('a crossfade moves the picture without dropping it', () {
    late _TwoPlayerSink players;

    setUp(() {
      players = _TwoPlayerSink();
      surface.sink = players;
    });

    test('the picture follows the fade onto the incoming player', () async {
      surface.claim(VideoHost.card);
      await pumpEventQueue();
      expect(players.showing, 'A', reason: 'the first video is on screen');

      // What HypeAudioHandler does at onCrossfadeStarted: the incoming player
      // is now the audible one, and the surface is asked to follow it.
      players.current = 'B';
      surface.rebind();
      await pumpEventQueue();

      expect(players.showing, 'B',
          reason: 'the video is still on screen and playing, so the surface '
              'must end up on the player that is now audible — anything else '
              'is a black stage the user has to leave the page to fix');
    });

    test('the swap at the end of the fade rebinds again, harmlessly', () async {
      surface.claim(VideoHost.card);
      players.current = 'B';
      surface.rebind(); // onCrossfadeStarted
      await pumpEventQueue();
      surface.rebind(); // onPlayerSwapped, same audible player
      await pumpEventQueue();

      expect(players.showing, 'B',
          reason: 'the second rebind of a crossfade must not take back the '
              'picture the first one just handed over');
    });

    test('rebinding with nobody watching attaches nothing', () async {
      surface.claim(VideoHost.card);
      await pumpEventQueue();
      surface.release(VideoHost.card);
      players.current = 'B';
      surface.rebind();
      await pumpEventQueue();

      expect(players.showing, isNull,
          reason: 'a queue playing on with no video host mounted should not '
              'be decoding frames for nobody');
    });
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
