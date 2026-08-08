/// The screen's brightness, for the swipe gesture on the video screen.
///
/// # Two platforms, two lifetimes
///
/// On Android this is a *window* override: it needs no permission, applies only
/// while this app is in front, and the system drops it when the window goes
/// away. On iOS there is no such thing — `UIScreen.brightness` is the device
/// setting, and it persists. So the video screen restores what it found on the
/// way out, which is the right behaviour on Android too and merely redundant
/// there.
///
/// A missing implementation is not an error worth surfacing: the gesture simply
/// does nothing, which is what would happen on a platform with no brightness
/// control anyway.
library;

import 'package:flutter/services.dart';

class ScreenBrightness {
  const ScreenBrightness._();

  static const _channel = MethodChannel('eq_app/screen_brightness');

  /// The current brightness in 0..1, or null when the platform has not been
  /// asked to override it and is deciding for itself.
  static Future<double?> get() async {
    try {
      return await _channel.invokeMethod<double>('get');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> set(double value) async {
    try {
      await _channel.invokeMethod<void>('set', {
        'value': value.clamp(0.0, 1.0),
      });
    } on PlatformException {
      // Nothing to do about it, and nothing the user could do either.
    } on MissingPluginException {
      // No brightness control on this platform.
    }
  }

  /// Hands control back to the system.
  ///
  /// Android takes this literally — the window override is cleared. iOS has no
  /// equivalent, so [restore] is given the value that was found on the way in.
  static Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('set', {'value': null});
    } on PlatformException {
      // As above.
    } on MissingPluginException {
      // As above.
    }
  }
}
