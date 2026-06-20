import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'package:path_provider/path_provider.dart';

import 'remote_link.dart';
import 'stream_server.dart';

/// Foreground-service entry point (its own isolate). The sharing server itself
/// runs in the MAIN isolate — so the mDNS advertisement and library plugins
/// behave exactly as they do in the foreground — and this handler only hosts the
/// persistent notification and relays its "Stop" button back to the app.
@pragma('vm:entry-point')
void shareTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_ShareTaskHandler());
}

class _ShareTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') FlutterForegroundTask.sendDataToMain('stop');
  }

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

/// Controls music-sharing. The server runs in-process (`StreamServerController`);
/// on Android a foreground service is layered on so the OS keeps the app — and
/// therefore the server — alive in the background, with a persistent
/// notification. The UI listens to this facade.
class ShareService extends ChangeNotifier {
  ShareService._();
  static final ShareService instance = ShareService._();

  final StreamServerController _server = StreamServerController.instance;
  bool get _withService => Platform.isAndroid;

  bool _busy = false;
  bool _inited = false;

  bool get running => _server.running;
  bool get busy => _busy;
  String? get pin => _server.pin;
  String? get ip => _server.ip;
  int? get port => _server.port;
  List<PairedDesktop> get pairedDesktops => _server.pairedDesktops;
  String get deviceName => _server.deviceName;

  String get _notificationText {
    final n = _server.pairedDesktops.length;
    return n == 0
        ? 'Ready to pair — code ${_server.pin ?? "------"}'
        : '$n computer${n == 1 ? "" : "s"} paired';
  }

  /// Call once at startup.
  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    _server.addListener(_onServerChanged);
    if (_withService) {
      FlutterForegroundTask.initCommunicationPort();
      FlutterForegroundTask.addTaskDataCallback(_onTaskData);
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'hype_share',
          channelName: 'Music sharing',
          channelDescription:
              'Shown while your music is being shared to the desktop app.',
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          autoRunOnBoot: false,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
      // A leftover service with no server running (rare) — clear it.
      if (await FlutterForegroundTask.isRunningService && !_server.running) {
        await FlutterForegroundTask.stopService();
      }
    }
  }

  Future<void> toggle(bool on) => on ? enable() : disable();

  Future<void> enable() async {
    if (_server.running || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      await _server.start();
      await _startRemoteLink();
      if (_withService) {
        await _requestPermissions();
        await FlutterForegroundTask.startService(
          serviceId: 5210,
          notificationTitle: 'Sharing music to desktop',
          notificationText: _notificationText,
          notificationButtons: const [
            NotificationButton(id: 'stop', text: 'Stop sharing'),
          ],
          callback: shareTaskCallback,
        );
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> disable() async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      if (_withService && await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
      await RemoteLink.instance.stop();
      await _server.stop();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Start this phone's iroh endpoint so desktops can reach it across networks
  /// (best-effort — sharing still works on the LAN if the native lib is absent).
  Future<void> _startRemoteLink() async {
    if (!remoteLinkSupported) return;
    final port = _server.port;
    if (port == null) return;
    try {
      final dir = await getApplicationSupportDirectory();
      await RemoteLink.instance.start('${dir.path}/remote-identity.bin', port);
    } catch (e) {
      debugPrint('ShareService: remote link unavailable: $e');
    }
  }

  void unpair(String id) => _server.unpair(id);

  void _onServerChanged() {
    notifyListeners();
    // Keep the notification text in sync (e.g. when a computer pairs).
    if (_withService && _server.running) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'Sharing music to desktop',
        notificationText: _notificationText,
      );
    }
  }

  void _onTaskData(Object data) {
    if (data == 'stop') disable();
  }

  Future<void> _requestPermissions() async {
    final perm = await FlutterForegroundTask.checkNotificationPermission();
    if (perm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }
}
