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
}

/// The real sink: the video output of whichever player is currently audible.
class _PlayerVideoSink implements VideoSink {
  const _PlayerVideoSink();

  @override
  void attach() => AppController.instance.handler.video.attach();

  @override
  void detach() => AppController.instance.handler.video.detach();
}

class VideoSurface extends ChangeNotifier with WidgetsBindingObserver {
  VideoSurface._() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final VideoSurface instance = VideoSurface._();

  VideoSink _sink = const _PlayerVideoSink();

  @visibleForTesting
  set sink(VideoSink value) => _sink = value;

  final Set<VideoHost> _claims = {};

  /// True while the app is in the foreground. A background app draws nothing,
  /// so it should not be decoding either — see the library comment.
  bool _foreground = true;

  /// The host that should draw, or null when the video is not being shown.
  VideoHost? get owner {
    if (!_foreground || _claims.isEmpty) return null;
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _sync();
    _announce();
  }

  /// Brings the native surface into line with whether anyone is watching.
  void _sync() {
    if (owner != null) {
      _sink.attach();
    } else {
      _sink.detach();
    }
  }

  @visibleForTesting
  void resetForTest() {
    _claims.clear();
    _foreground = true;
    _sink = const _PlayerVideoSink();
  }

  @visibleForTesting
  void setForegroundForTest(bool value) {
    didChangeAppLifecycleState(
      value ? AppLifecycleState.resumed : AppLifecycleState.paused,
    );
  }
}
