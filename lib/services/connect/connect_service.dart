/// Keeping Hype Connect alive in the background on Android.
///
/// # Why a service
///
/// A socket held by an app in the background lives only as long as Android lets
/// the process live. A foreground service — `ConnectService` on the native
/// side, with a persistent notification — is the platform's way of saying "the
/// user knows this is running", and in return the process is not frozen or
/// reclaimed. The notification is also where the user sees what is happening
/// and turns the whole thing off.
///
/// # Who starts it, and when
///
/// Android 12+ forbids starting a foreground service from the background, so
/// Dart starts it only while the app is on screen: when Hype Connect is turned
/// on, and again on resume if it is wanted but not running. After a reboot (or
/// an app update) a native receiver starts it, which is allowed for boot
/// broadcasts; that receiver reads a flag this class mirrors into native
/// preferences ([ConnectServiceBridge.setBootEnabled]).
///
/// # What it runs when
///
/// The service runs while Hype Connect is on **and** the app is a music player
/// — the same rule as the socket itself ([ConnectPresence]). Leaving the
/// equalizer-only mode stops it, returning starts it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'connect_notification.dart';

/// The native service, as Dart sees it.
abstract interface class ConnectServiceBridge {
  /// Whether the service is up. False when the platform cannot say.
  Future<bool> isRunning();

  /// Starts the service. False when the platform refused (e.g. the app was not
  /// in a state allowed to start one) — the caller tries again on resume.
  Future<bool> start();

  Future<void> update(ConnectNotificationContent content);

  Future<void> stop();

  /// Remembers, natively, whether the service should come up after a reboot.
  Future<void> setBootEnabled(bool enabled);

  /// Whether the system has exempted the app from battery optimisation.
  Future<bool> isIgnoringBatteryOptimizations();

  /// Opens the system page where the user can exempt the app.
  Future<void> openBatterySettings();

  /// Whether the notification was tapped since this was last asked. Reading it
  /// clears it.
  Future<bool> takeOpenRequest();

  /// The system media volume as 0..1; null when the platform cannot say (iOS,
  /// a test engine), in which case the caller falls back to the player gain.
  Future<double?> getVolume();

  /// Sets the system media volume (0..1) silently. False when unavailable.
  Future<bool> setVolume(double value);

  /// Starts or stops [onVolumeChanged] events for the media stream.
  Future<void> watchVolume(bool on);

  /// While on, the hardware volume keys do not touch this phone: they arrive
  /// as [onVolumeKey] instead (this phone is a remote for another player).
  Future<void> setRemoteVolumeKeys(bool on);

  /// Notification button taps and "open the Hype Connect page" requests.
  set onAction(void Function(String id)? handler);
  set onOpenRequested(void Function()? handler);

  /// The system media volume changed (0..1) while watched.
  set onVolumeChanged(void Function(double value)? handler);

  /// A hardware volume key was pressed in remote-keys mode: "up" or "down".
  set onVolumeKey(void Function(String direction)? handler);
}

/// The real thing: `x.a.zix/connect_service`, handled by `ConnectChannel.java`.
///
/// Every call degrades to "not available" when the native side is not there
/// (a plugin-less test engine, or a native handler not yet registered), so a
/// missing channel never breaks Hype Connect itself.
class MethodChannelConnectService implements ConnectServiceBridge {
  MethodChannelConnectService([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel('x.a.zix/connect_service') {
    _channel.setMethodCallHandler(_fromNative);
  }

  final MethodChannel _channel;
  void Function(String id)? _onAction;
  void Function()? _onOpenRequested;
  void Function(double value)? _onVolumeChanged;
  void Function(String direction)? _onVolumeKey;

  Future<dynamic> _fromNative(MethodCall call) async {
    switch (call.method) {
      case 'action':
        _onAction?.call(call.arguments as String);
      case 'openRequested':
        _onOpenRequested?.call();
      case 'volumeChanged':
        final value = call.arguments;
        if (value is num) _onVolumeChanged?.call(value.toDouble().clamp(0.0, 1.0));
      case 'volumeKey':
        final direction = call.arguments;
        if (direction is String) _onVolumeKey?.call(direction);
    }
    return null;
  }

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      debugPrint('Hype Connect service: $method failed: ${e.message}');
    } on MissingPluginException {
      debugPrint('Hype Connect service: $method has no native handler');
    }
    return null;
  }

  @override
  set onAction(void Function(String id)? handler) => _onAction = handler;

  @override
  set onOpenRequested(void Function()? handler) => _onOpenRequested = handler;

  @override
  set onVolumeChanged(void Function(double value)? handler) =>
      _onVolumeChanged = handler;

  @override
  set onVolumeKey(void Function(String direction)? handler) =>
      _onVolumeKey = handler;

  @override
  Future<double?> getVolume() async {
    final value = await _call<double>('getVolume');
    return value?.clamp(0.0, 1.0);
  }

  @override
  Future<bool> setVolume(double value) async {
    // Not through _call: a void reply and a failure are both null there, and
    // the caller needs to tell them apart to fall back to the player gain.
    try {
      await _channel.invokeMethod<void>('setVolume', value);
      return true;
    } on PlatformException catch (e) {
      debugPrint('Hype Connect service: setVolume failed: ${e.message}');
    } on MissingPluginException {
      debugPrint('Hype Connect service: setVolume has no native handler');
    }
    return false;
  }

  @override
  Future<void> watchVolume(bool on) => _call<void>('watchVolume', on);

  @override
  Future<void> setRemoteVolumeKeys(bool on) =>
      _call<void>('setRemoteVolumeKeys', on);

  @override
  Future<bool> isRunning() async => await _call<bool>('isRunning') ?? false;

  @override
  Future<bool> start() async => await _call<bool>('start') ?? false;

  @override
  Future<void> update(ConnectNotificationContent content) =>
      _call<void>('update', content.toJson());

  @override
  Future<void> stop() => _call<void>('stop');

  @override
  Future<void> setBootEnabled(bool enabled) =>
      _call<void>('setBootEnabled', enabled);

  @override
  Future<bool> isIgnoringBatteryOptimizations() async =>
      // Unknown means "do not nag".
      await _call<bool>('isIgnoringBatteryOptimizations') ?? true;

  @override
  Future<void> openBatterySettings() => _call<void>('openBatterySettings');

  @override
  Future<bool> takeOpenRequest() async =>
      await _call<bool>('takeOpenRequest') ?? false;
}

/// Decides when the service runs and what its notification says.
///
/// Fed three things — whether the service is wanted, whether the app is on
/// screen, and (through [content]) what to say — it starts and stops the
/// service and pushes the notification, never more than one update per
/// [throttle] and never an update that changes nothing.
class ConnectServiceController {
  ConnectServiceController({
    required this.bridge,
    required this.content,
    this.requestNotifications,
    this.throttle = const Duration(seconds: 1),
  });

  final ConnectServiceBridge bridge;

  /// The notification as it should read right now.
  final ConnectNotificationContent Function() content;

  /// Asks for the Android 13+ notification permission. Called only when the
  /// user turns Hype Connect on, since only then is there an activity to ask
  /// from and a reason to give.
  final Future<void> Function()? requestNotifications;

  final Duration throttle;

  bool _wanted = false;
  bool _foreground = true;

  /// Null until native has been asked.
  bool? _running;
  bool? _bootEnabled;
  bool _starting = false;

  ConnectNotificationContent? _pushed;
  Timer? _cooldown;
  bool _dirty = false;

  /// Whether the service is believed to be up.
  bool get running => _running ?? false;

  /// Learns whether the service is already up (a boot start, or one from
  /// before this process's Dart side restarted) and only then applies the
  /// first [wanted] / [foreground].
  ///
  /// The order matters after a reboot: native has started the service and the
  /// app has no screen, so a start request now would be refused, and a "not
  /// wanted yet" default would stop a service that is exactly right.
  Future<void> init({required bool wanted, required bool foreground}) async {
    _wanted = wanted;
    _foreground = foreground;
    _running = await bridge.isRunning();
    _reconcile();
  }

  /// The service should run (Hype Connect on and in music-player mode).
  void setWanted(bool wanted) {
    if (_wanted == wanted) return;
    _wanted = wanted;
    _reconcile();
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    _reconcile();
  }

  /// The user just turned Hype Connect on: ask for the notification permission
  /// before the service starts, so its first notification can be seen.
  Future<void> userEnabled() async {
    final ask = requestNotifications;
    if (ask == null) return;
    try {
      await ask();
    } catch (e) {
      // No activity to ask from, or the plugin is busy: the service still
      // runs, its notification just sits in the task manager.
      debugPrint('Hype Connect service: notification permission: $e');
    }
  }

  /// Something the notification depends on may have changed.
  void refresh() {
    if (_wanted && running) _push();
  }

  void _reconcile() {
    final wanted = _wanted;
    if (_bootEnabled != wanted) {
      _bootEnabled = wanted;
      unawaited(bridge.setBootEnabled(wanted));
    }
    if (!wanted) {
      _cooldown?.cancel();
      _cooldown = null;
      _dirty = false;
      _pushed = null;
      // Also when unknown: stopping a service that is not running is free, and
      // one left over from before is exactly what must not survive.
      if (_running != false) {
        _running = false;
        unawaited(bridge.stop());
      }
      return;
    }
    if (_running == true) {
      _push();
      return;
    }
    if (_foreground && !_starting) unawaited(_start());
  }

  Future<void> _start() async {
    _starting = true;
    try {
      final ok = await bridge.start();
      _running = ok;
      _pushed = null;
    } finally {
      _starting = false;
    }
    // Wanted may have flipped while the start was in flight.
    if (!_wanted && _running == true) {
      _running = false;
      unawaited(bridge.stop());
      return;
    }
    if (_running == true) _push();
  }

  void _push() {
    if (_cooldown != null) {
      _dirty = true;
      return;
    }
    final next = content();
    if (next == _pushed) return;
    _pushed = next;
    unawaited(bridge.update(next));
    _cooldown = Timer(throttle, () {
      _cooldown = null;
      if (_dirty) {
        _dirty = false;
        if (_wanted && running) _push();
      }
    });
  }

  void dispose() {
    _cooldown?.cancel();
    _cooldown = null;
  }
}
