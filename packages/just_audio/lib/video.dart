/// Video output for the player that already plays the music.
///
/// # Why this lives here rather than in a plugin of its own
///
/// The engine behind [AudioPlayer] on Android is ExoPlayer and on iOS is
/// AVPlayer — the same engines a video plugin would wrap. Wrapping one *again*
/// would mean a second player, and a second player is precisely the arrangement
/// that broke: two of them cannot share one output, so the music had to be
/// paused for a video to be heard; the video's audio never travelled through the
/// DSP chain that gives this app its equaliser; the video was not in the queue,
/// so nothing followed it; and it was not inside the background audio service,
/// so it stopped at the lock screen.
///
/// Giving the existing player a surface answers all four at once, because none
/// of them were video problems. They were consequences of there being two
/// players.
///
/// # The texture is only alive while something is watching
///
/// [attach] creates a platform texture; [detach] releases it *and disables the
/// video track*. That second part is the point: a phone whose screen is off
/// should not be decoding frames, and on a metered connection it should not be
/// paying for them. Backgrounding a music video reduces it to the audio stream
/// it would otherwise have been, and returning restores the picture.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';

import 'just_audio.dart';

/// One selectable video rendition of the current item.
@immutable
class VideoRendition {
  final int width;
  final int height;
  final int bitrate;
  final double frameRate;
  final String codecs;

  const VideoRendition({
    required this.width,
    required this.height,
    required this.bitrate,
    required this.frameRate,
    required this.codecs,
  });

  factory VideoRendition.fromMap(Map<dynamic, dynamic> map) => VideoRendition(
        width: (map['width'] as num?)?.toInt() ?? 0,
        height: (map['height'] as num?)?.toInt() ?? 0,
        bitrate: (map['bitrate'] as num?)?.toInt() ?? 0,
        frameRate: (map['frameRate'] as num?)?.toDouble() ?? 0,
        codecs: map['codecs'] as String? ?? '',
      );

  /// How a quality menu names this rendition — `1080p`, `720p60`.
  ///
  /// Height rather than width because that is the number people know, and the
  /// frame rate only when it is above the ordinary: `720p60` is a meaningful
  /// distinction from `720p`, while `720p30` is just noise.
  String get label {
    final rate = frameRate >= 50 ? frameRate.round().toString() : '';
    return '${height}p$rate';
  }

  @override
  bool operator ==(Object other) =>
      other is VideoRendition &&
      other.width == width &&
      other.height == height &&
      other.bitrate == bitrate;

  @override
  int get hashCode => Object.hash(width, height, bitrate);
}

/// What the platform last said about the video it is rendering.
@immutable
class VideoState {
  final int width;
  final int height;
  final double pixelAspectRatio;

  /// Every rendition on offer, largest first. Empty for an audio-only item.
  final List<VideoRendition> renditions;

  /// Index into [renditions], or -1 when quality is chosen adaptively.
  final int selectedIndex;

  const VideoState({
    this.width = 0,
    this.height = 0,
    this.pixelAspectRatio = 1,
    this.renditions = const [],
    this.selectedIndex = -1,
  });

  factory VideoState.fromMap(Map<dynamic, dynamic> map) => VideoState(
        width: (map['width'] as num?)?.toInt() ?? 0,
        height: (map['height'] as num?)?.toInt() ?? 0,
        pixelAspectRatio: (map['pixelAspectRatio'] as num?)?.toDouble() ?? 1,
        renditions: [
          for (final rendition in (map['renditions'] as List? ?? const []))
            VideoRendition.fromMap(rendition as Map),
        ],
        selectedIndex: (map['selected'] as num?)?.toInt() ?? -1,
      );

  bool get hasVideo => width > 0 && height > 0;

  /// The shape to draw this video in, or 16:9 before the first frame arrives.
  ///
  /// A fallback is needed rather than nothing: the surface has to be laid out
  /// before there is a frame to measure, and a zero-area box would collapse the
  /// layout around it and then jump.
  double get aspectRatio {
    if (!hasVideo) return 16 / 9;
    final ratio = width * pixelAspectRatio / height;
    return ratio > 0 ? ratio : 16 / 9;
  }

  /// True when the user has pinned a rendition rather than leaving it adaptive.
  bool get isPinned => selectedIndex >= 0 && selectedIndex < renditions.length;

  VideoRendition? get selected => isPinned ? renditions[selectedIndex] : null;

  @override
  bool operator ==(Object other) =>
      other is VideoState &&
      other.width == width &&
      other.height == height &&
      other.selectedIndex == selectedIndex &&
      listEquals(other.renditions, renditions);

  @override
  int get hashCode => Object.hash(width, height, selectedIndex, renditions.length);
}

/// The video surface of one [AudioPlayer].
///
/// One per player, created on demand and kept for the player's lifetime — the
/// selected quality and the last known size are worth more than the few bytes
/// they cost, and both would otherwise be forgotten every time the user leaves
/// the video screen.
class VideoOutput {
  static const _methods = MethodChannel('com.ryanheise.just_audio.video');

  final AudioPlayer player;

  /// The platform texture to draw, or null while nothing is attached.
  ///
  /// A [ValueNotifier] rather than a stream because widgets are the only
  /// consumer and this is exactly the shape they want.
  final ValueNotifier<int?> texture = ValueNotifier<int?>(null);

  final _stateSubject = BehaviorSubject<VideoState>.seeded(const VideoState());

  StreamSubscription<dynamic>? _eventSubscription;
  StreamSubscription<String?>? _platformIdSubscription;

  /// The id the current subscription and texture belong to.
  String? _boundId;

  /// Whether the app wants a picture right now, as distinct from whether it
  /// currently has one. Attaching is asynchronous and the platform player can be
  /// replaced underneath it, so intent has to be recorded separately from state.
  bool _wanted = false;
  bool _disposed = false;

  /// Whether a picture is wanted on this player right now.
  ///
  /// Exposed because this flag is the bug: a detach that lands on top of an
  /// in-flight attach clears it, and the attach then undoes itself on arrival —
  /// invisible from the outside, since the symptom is simply a texture that
  /// never appears.
  @visibleForTesting
  bool get isWanted => _wanted;

  VideoOutput(this.player) {
    _platformIdSubscription = player.platformIdStream.listen((id) {
      // A new platform player is a new native surface. Rebind if the picture is
      // still wanted; forget the stale texture either way, because the id it
      // referred to is gone and drawing it would show the last frame forever.
      if (id == _boundId) return;
      _boundId = null;
      texture.value = null;
      _eventSubscription?.cancel();
      _eventSubscription = null;
      if (_wanted) unawaited(_bind());
    });
  }

  Stream<VideoState> get stateStream => _stateSubject.stream;

  VideoState get state => _stateSubject.value;

  /// Asks for the picture and returns the texture id, or null if the platform
  /// player has gone away in the meantime.
  ///
  /// Safe to call repeatedly — the platform returns the texture already in use
  /// rather than creating another.
  Future<int?> attach() async {
    _wanted = true;
    return _bind();
  }

  Future<int?> _bind() async {
    final id = player.platformId;
    if (id == null || _disposed) return null;

    _eventSubscription ??= EventChannel('com.ryanheise.just_audio.video.$id')
        .receiveBroadcastStream()
        .listen(
      (event) {
        if (event is Map && !_stateSubject.isClosed) {
          _stateSubject.add(VideoState.fromMap(event));
        }
      },
      // A player torn down mid-stream closes its channel. That is a lifecycle
      // event, not a failure worth surfacing.
      onError: (Object _) {},
    );

    final result = await _invoke<int>('attachVideo', id);
    if (_disposed || !_wanted) {
      // Detached while the attach was in flight. Leaving the surface bound
      // would keep the video decoder running behind a screen nobody is looking
      // at — the exact cost this class exists to avoid.
      if (result != null) await _invoke<void>('detachVideo', id);
      return null;
    }
    _boundId = id;
    texture.value = result;
    return result;
  }

  /// Gives the surface back and stops decoding video. Audio carries on.
  Future<void> detach() async {
    _wanted = false;
    final id = _boundId ?? player.platformId;
    texture.value = null;
    _boundId = null;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    if (id != null) await _invoke<void>('detachVideo', id);
  }

  /// Pins [rendition], or restores adaptive selection when it is null.
  Future<void> selectQuality(VideoRendition? rendition) {
    final index =
        rendition == null ? -1 : state.renditions.indexOf(rendition);
    return selectQualityAt(index);
  }

  /// Pins the rendition at [index] in [VideoState.renditions]; -1 is adaptive.
  Future<void> selectQualityAt(int index) async {
    final id = player.platformId;
    if (id == null) return;
    await _invoke<void>('selectVideoQuality', id, {'index': index});
  }

  Future<T?> _invoke<T>(String method, String id, [Map<String, Object?>? extra]) async {
    try {
      return await _methods.invokeMethod<T>(method, {'id': id, ...?extra});
    } on PlatformException {
      // The player this addressed no longer exists. The caller gets nothing,
      // which is the truth, and the next attach will bind to whatever replaced
      // it.
      return null;
    } on MissingPluginException {
      // Platform without video output (web, tests). Audio is unaffected.
      return null;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await detach();
    await _platformIdSubscription?.cancel();
    await _stateSubject.close();
    texture.dispose();
  }
}
