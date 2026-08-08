/// The video, floating over whatever the user does next.
///
/// # What the platform actually gives us
///
/// Flutter draws the whole app into one window, and picture-in-picture shrinks
/// *that window*. So entering the mode does not extract the video — it
/// miniaturises the entire player screen, controls and all, unless the app
/// notices and draws only the video for as long as the mode lasts. [isActive]
/// is what the widget tree watches to do that.
///
/// # Leaving the app is the gesture
///
/// Android offers exactly one callback for "the user pressed home", and it is
/// the moment PiP has to be entered — asking later is refused. So intent is
/// registered ahead of time with [setAutoEnter] and the platform acts on it
/// when the moment comes, rather than the app trying to detect the moment
/// itself.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PictureInPicture {
  PictureInPicture._();

  static final PictureInPicture instance = PictureInPicture._();

  /// Android's floating window is a property of the Activity; iOS's is driven
  /// from the player's own layer, and this app's player lives inside the
  /// vendored `just_audio`. So the two platforms answer on different channels —
  /// but they answer the same three methods and push back the same `changed`,
  /// which is why the difference stops here.
  static final MethodChannel _channel = Platform.isIOS
      ? const MethodChannel('com.ryanheise.just_audio.pip')
      : const MethodChannel('eq_app/pip');

  /// Whether the app is currently a floating window.
  final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);

  bool _supported = false;
  bool _wired = false;

  /// Whether this device offers picture-in-picture at all.
  ///
  /// Asked once at launch, because the answer decides whether the affordance is
  /// offered — and a button that does nothing is worse than no button.
  bool get isSupported => _supported;

  /// Asks the platform what it can do and starts listening for mode changes.
  Future<void> init() async {
    if (_wired) return;
    _wired = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') {
        isActive.value = call.arguments == true;
      }
      return null;
    });
    try {
      _supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      _supported = false;
    } on MissingPluginException {
      // A platform with no picture-in-picture. The rest of the app is unchanged.
      _supported = false;
    }
  }

  /// Registers that leaving the app should float the video, and its shape.
  ///
  /// Called whenever a video starts, stops or changes size — not at the moment
  /// of leaving, which is too late to ask.
  Future<void> setAutoEnter({
    required bool on,
    int? width,
    int? height,
  }) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('setAutoEnter', {
        'on': on,
        if (width != null && width > 0) 'width': width,
        if (height != null && height > 0) 'height': height,
      });
    } on PlatformException {
      // Nothing to do about it; the video simply will not float.
    } on MissingPluginException {
      // As above.
    }
  }

  /// Floats the video now, for a button rather than a gesture.
  ///
  /// Returns whether the platform accepted — it refuses when the activity is
  /// not in a state that allows it, and the caller should not pretend otherwise.
  Future<bool> enter({int? width, int? height}) async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('enter', {
            if (width != null && width > 0) 'width': width,
            if (height != null && height > 0) 'height': height,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
