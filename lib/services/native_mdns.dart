import 'dart:io';

import 'package:flutter/services.dart';

/// Thin bridge to the native Android `NsdManager` + `WifiManager.MulticastLock`
/// (see `android/app/src/main/kotlin/x/a/zix/HypeMdns.java`).
///
/// Why native rather than the `bonsoir` plugin on Android:
///  * `NsdManager.registerService` is a *process-level* system-service call. It
///    is isolate-agnostic, so it works from the `flutter_foreground_task`
///    background isolate — where `bonsoir`, whose platform channel is bound to
///    that secondary `FlutterEngine`, previously advertised *silently* (the
///    desktop never saw it). See commit 9834722 for the regression this fixes.
///  * A held `MulticastLock` stops Android's Wi‑Fi power-saving from dropping
///    the inbound mDNS queries the desktop sends, so the phone stays
///    discoverable while backgrounded.
///
/// No-op on non-Android platforms — iOS keeps advertising through `bonsoir`,
/// which behaves correctly there.
class NativeMdns {
  const NativeMdns._();

  static const MethodChannel _channel = MethodChannel('x.a.zix/mdns');

  /// Whether the native mDNS path is available (Android only).
  static bool get supported => Platform.isAndroid;

  /// Register (or re-register) the DNS-SD service. Idempotent on the native
  /// side — any prior registration is withdrawn first.
  static Future<void> register({
    required String name,
    required String type,
    required int port,
    required Map<String, String> txt,
  }) async {
    if (!supported) return;
    await _channel.invokeMethod<void>('registerService', <String, Object>{
      'name': name,
      'type': type,
      'port': port,
      'txt': txt,
    });
  }

  /// Withdraw the advertisement. Safe to call when nothing is registered.
  static Future<void> unregister() async {
    if (!supported) return;
    await _channel.invokeMethod<void>('unregisterService');
  }

  /// Hold a Wi‑Fi multicast lock so inbound mDNS queries keep arriving while the
  /// phone is idle/backgrounded. Reference-counted off on the native side, so
  /// repeated acquires are harmless.
  static Future<void> acquireMulticastLock() async {
    if (!supported) return;
    await _channel.invokeMethod<void>('acquireMulticastLock');
  }

  /// Release the multicast lock. Safe to call when none is held.
  static Future<void> releaseMulticastLock() async {
    if (!supported) return;
    await _channel.invokeMethod<void>('releaseMulticastLock');
  }
}
