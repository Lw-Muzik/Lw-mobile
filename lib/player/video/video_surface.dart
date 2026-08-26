/// Who is showing the video right now.
///
/// # One stream, several places it can appear
///
/// There is exactly one video surface — one texture, fed by one decoder — and
/// three widgets that may want it: the card on the player screen, a full-screen
/// route above it, and a floating mini player that follows the user around the
/// app. Two of them can easily be mounted at the same time: opening full screen
/// does not unmount the card beneath it.
///
/// So the surface is claimed rather than grabbed. Every host registers its
/// interest and reads back whether it is the one that should draw; the most
/// specific claim wins. Full screen outranks the mini player, which outranks the
/// card, because that is the order in which the user is looking at them.
///
/// # Nobody claiming means nobody decoding
///
/// The native surface is attached when the first claim arrives and released when
/// the last one goes — and releasing it disables the video track, so a video
/// with no viewer costs no decoding and, on a metered connection, no bytes. That
/// includes the app being sent to the background, which this class watches for
/// itself rather than trusting each host to remember.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../controllers/AppController.dart';
import '../../services/screen_brightness.dart';
import 'picture_in_picture.dart';

/// The places a video can be shown, in ascending order of precedence.
enum VideoHost {
  /// The floating window that follows the user through the rest of the app.
  ///
  /// Lowest, because it exists precisely for when neither of the others is on
  /// screen — it steps aside the moment the player itself is showing.
  mini,

  /// The card on the player screen.
  card,

  /// A route covering everything else.
  fullscreen,

  /// The system's floating window.
  ///
  /// Highest, because when the whole app has been shrunk into a thumbnail the
  /// only thing worth drawing in it is the video — every other host is still
  /// mounted underneath, and every one of them should stand down.
  pip,
}

/// What a claim ultimately turns into: a surface handed to the player, or taken
/// back from it.
///
/// Named so this class can be reasoned about — and tested — without a platform
/// player behind it. The precedence rules are the interesting part and they are
/// pure logic; wiring them to a decoder is one line at the bottom of the file.
abstract class VideoSink {
  void attach();
  void detach();

  /// Releases every surface *except* the one belonging to the player that is
  /// audible now. See [VideoSurface.rebind].
  ///
  /// "Except" is the whole point, and it is why this is not `detachAll`. There
  /// are two players and the surface has to end up on one particular one of
  /// them; a detach that sweeps up all of them is asynchronous, so it arrives
  /// after the attach that was supposed to follow it and takes the picture
  /// straight back off the screen. Naming the survivor makes that unsayable.
  Future<void> detachOthers();

  /// Whether leaving the app should float the video, and at what shape.
  void setFloatOnLeave(bool on);

  /// Whether the screen should be held awake.
  ///
  /// Belongs here rather than in a widget because it answers the same question
  /// attaching does — is a picture on screen — and answering it twice, in two
  /// places, is how the two get out of step and the screen stays lit over a
  /// player that closed.
  void keepAwake(bool on);
}

/// The real sink: the video output of whichever player is currently audible.
class _PlayerVideoSink implements VideoSink {
  const _PlayerVideoSink();

  @override
  void attach() => AppController.instance.handler.video.attach();

  @override
  void detach() => AppController.instance.handler.video.detach();

  @override
  Future<void> detachOthers() {
    final handler = AppController.instance.handler;
    return handler.detachAllVideo(except: handler.currentTrackPlayer);
  }

  @override
  void setFloatOnLeave(bool on) {
    final state = AppController.instance.handler.video.state;
    PictureInPicture.instance.setAutoEnter(
      on: on,
      width: state.hasVideo ? state.width : null,
      height: state.hasVideo ? state.height : null,
    );
  }

  @override
  void keepAwake(bool on) => ScreenBrightness.keepAwake(on);
}

class VideoSurface extends ChangeNotifier with WidgetsBindingObserver {
  VideoSurface._() {
    WidgetsBinding.instance.addObserver(this);
    // A floating window backgrounds the app while the video is still very much
    // on screen. Without this the lifecycle handler below would tear the
    // surface down the instant picture-in-picture started — on Android that is
    // a black thumbnail, on iOS a video dropped to its lowest rendition.
    PictureInPicture.instance.isActive.addListener(_onFloatingChanged);
  }

  void _onFloatingChanged() {
    _sync();
    _announce();
  }

  static final VideoSurface instance = VideoSurface._();

  VideoSink _sink = const _PlayerVideoSink();

  @visibleForTesting
  set sink(VideoSink value) => _sink = value;

  final Set<VideoHost> _claims = {};

  /// True while the app is in the foreground. A background app draws nothing,
  /// so it should not be decoding either — see the library comment.
  bool _foreground = true;

  /// Whether the video is on screen anywhere.
  ///
  /// Being in the background is not the same as being invisible: a floating
  /// window outlives the app going away, and is the one case where a
  /// backgrounded app should go on decoding.
  bool get _visible => _foreground || PictureInPicture.instance.isActive.value;

  /// The host that should draw, or null when the video is not being shown.
  VideoHost? get owner {
    if (!_visible || _claims.isEmpty) return null;
    for (final host in VideoHost.values.reversed) {
      if (_claims.contains(host)) return host;
    }
    return null;
  }

  bool isOwner(VideoHost host) => owner == host;

  /// Whether any host other than [host] is currently showing the video.
  ///
  /// The mini player asks this to decide whether to appear at all: it is for
  /// the times the player screen is not on top, and a floating copy of a video
  /// the user is already watching full-size is clutter.
  bool claimedByOther(VideoHost host) =>
      _claims.any((claim) => claim != host);

  /// The texture to draw, or null while nothing is attached.
  ValueListenable<int?> get texture =>
      AppController.instance.handler.video.texture;

  void claim(VideoHost host) {
    if (!_claims.add(host)) return;
    _sync();
    _announce();
  }

  void release(VideoHost host) {
    if (!_claims.remove(host)) return;
    _sync();
    _announce();
  }

  /// Tells listeners the owner changed, without doing so mid-build.
  ///
  /// Claims arrive from `initState` and releases from `dispose`, both of which
  /// run while the tree is being built or torn down. Notifying there would ask
  /// the widgets listening — including the one that just mounted — to rebuild
  /// during a build, which Flutter refuses outright. Deferring to the end of the
  /// frame costs one frame of the video being drawn by the outgoing host, and
  /// the alternative is an exception.
  void _announce() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      notifyListeners();
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
  }

  bool _disposed = false;

  /// Drops every claim. For a queue that has moved on to something with no
  /// picture, where leaving the surface attached would decode nothing and hold
  /// a texture forever.
  void releaseAll() {
    if (_claims.isEmpty) return;
    _claims.clear();
    _sync();
    _announce();
  }

  /// Moves the picture onto whichever player is now the audible one.
  ///
  /// Called when a crossfade starts and again when it swaps the players over.
  /// There are two players and a surface belongs to exactly one of them, so
  /// without this the video would keep drawing from the player the fade is
  /// about to stop: a frozen last frame over the next track's soundtrack.
  ///
  /// The incoming player is claimed *first* and the others released after.
  /// Doing it the other way round leaves a moment with no surface anywhere,
  /// which is a black flash at the exact instant the user is watching — and,
  /// when the release is not awaited, worse than a flash: it lands on top of
  /// the attach and cancels it, leaving the stage black until some host claims
  /// the surface again. The order here is the fix, not a preference.
  Future<void> rebind() async {
    if (owner != null) _sink.attach();
    _announce();
    await _sink.detachOthers();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _sync();
    _announce();
  }

  /// Brings the native surface — and the screen — into line with whether
  /// anyone is watching.
  ///
  /// A video the user is watching without touching is exactly the case the
  /// screen timeout gets wrong; a song is exactly the case it gets right. Since
  /// this is already the one place that knows which of the two is happening, it
  /// is the one place that decides.
  void _sync() {
    final watching = owner != null;
    if (watching) {
      _sink.attach();
    } else {
      _sink.detach();
    }
    if (watching != _awake) {
      _awake = watching;
      _sink.keepAwake(watching);
      // Registered here rather than at the moment of leaving, because Android
      // refuses the request once the app is already going away.
      _sink.setFloatOnLeave(watching);
    }
  }

  /// Whether the screen is currently being held on by this class.
  bool _awake = false;

  @visibleForTesting
  void resetForTest() {
    _claims.clear();
    _foreground = true;
    _awake = false;
    _sink = const _PlayerVideoSink();
  }

  @visibleForTesting
  void setForegroundForTest(bool value) {
    didChangeAppLifecycleState(
      value ? AppLifecycleState.resumed : AppLifecycleState.paused,
    );
  }
}
