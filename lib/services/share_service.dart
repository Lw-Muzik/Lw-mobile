import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'stream_server.dart';

/// Entry point the foreground service spins up in its own background isolate.
/// Must be a top-level function annotated for the VM.
@pragma('vm:entry-point')
void shareTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_ShareTaskHandler());
}

/// Runs the music-sharing server inside the foreground service's isolate, so it
/// keeps serving (and advertising over mDNS) even after the app is swiped from
/// recents. Relays its state to the UI isolate and keeps the notification fresh.
class _ShareTaskHandler extends TaskHandler {
  final StreamServerController _server = StreamServerController.instance;
  VoidCallback? _detach;

  void _relay() {
    FlutterForegroundTask.sendDataToMain(jsonEncode(_server.stateSnapshot()));
    final n = _server.pairedDesktops.length;
    FlutterForegroundTask.updateService(
      notificationTitle: 'Sharing music to desktop',
      notificationText: n == 0
          ? 'Ready to pair — code ${_server.pin ?? "------"}'
          : '$n computer${n == 1 ? "" : "s"} paired',
    );
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _server.addListener(_relay);
    _detach = () => _server.removeListener(_relay);
    await _server.start();
    _relay();
  }

  // No periodic work — the shelf server runs on its own; this just keeps the
  // isolate as the foreground service's host.
  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onReceiveData(Object data) {
    if (data == 'refresh') {
      _relay();
      return;
    }
    if (data is String) {
      try {
        final msg = jsonDecode(data) as Map<String, dynamic>;
        if (msg['cmd'] == 'unpair' && msg['id'] is String) {
          _server.unpair(msg['id'] as String);
        }
      } catch (_) {/* ignore malformed command */}
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') FlutterForegroundTask.stopService();
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _detach?.call();
    await _server.stop();
  }
}

/// Main-isolate facade the UI talks to. On Android it drives a foreground
/// service (so sharing survives the app being removed from memory and shows a
/// persistent notification); on iOS — where the OS suspends background apps —
/// it falls back to running the server in-process while the app is alive.
class ShareService extends ChangeNotifier {
  ShareService._();
  static final ShareService instance = ShareService._();

  bool get _useService => Platform.isAndroid;

  bool _running = false;
  bool _busy = false;
  String? _pin;
  String? _ip;
  int? _port;
  List<PairedDesktop> _paired = const [];
  bool _inited = false;

  bool get running => _running;
  bool get busy => _busy;
  String? get pin => _pin;
  String? get ip => _ip;
  int? get port => _port;
  List<PairedDesktop> get pairedDesktops => _paired;
  String get deviceName => Platform.isIOS ? 'iPhone' : 'Android phone';

  /// Call once at app startup (registers the task↔UI channel and restores the
  /// running state if the service is already up from a previous session).
  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    if (_useService) {
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
      _running = await FlutterForegroundTask.isRunningService;
      if (_running) FlutterForegroundTask.sendDataToTask('refresh');
    } else {
      StreamServerController.instance.addListener(_syncFromController);
    }
    notifyListeners();
  }

  Future<void> toggle(bool on) => on ? enable() : disable();

  /// Start sharing (and, on Android, the foreground service + notification).
  Future<void> enable() async {
    if (_running || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      if (_useService) {
        await _requestPermissions();
        await FlutterForegroundTask.startService(
          serviceId: 5210,
          notificationTitle: 'Sharing music to desktop',
          notificationText: 'Starting…',
          notificationButtons: const [
            NotificationButton(id: 'stop', text: 'Stop sharing'),
          ],
          callback: shareTaskCallback,
        );
        _running = true; // the task relays the real pin/port shortly after.
      } else {
        await StreamServerController.instance.start();
        _syncFromController();
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Stop sharing and tear down the service/notification.
  Future<void> disable() async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      if (_useService) {
        await FlutterForegroundTask.stopService();
      } else {
        await StreamServerController.instance.stop();
      }
    } finally {
      _running = false;
      _pin = null;
      _ip = null;
      _port = null;
      _paired = const [];
      _busy = false;
      notifyListeners();
    }
  }

  void unpair(String id) {
    if (_useService) {
      FlutterForegroundTask.sendDataToTask(jsonEncode({'cmd': 'unpair', 'id': id}));
    } else {
      StreamServerController.instance.unpair(id);
    }
  }

  // -- Android: state relayed from the service isolate -----------------------

  void _onTaskData(Object data) {
    if (data is! String) return;
    try {
      final s = jsonDecode(data) as Map<String, dynamic>;
      _running = s['running'] == true;
      _pin = s['pin'] as String?;
      _ip = s['ip'] as String?;
      _port = s['port'] as int?;
      _paired = ((s['paired'] as List?) ?? const [])
          .map((j) => PairedDesktop(
                id: (j as Map)['id'] as String,
                name: j['name'] as String,
                token: '', // tokens stay in the service isolate.
              ))
          .toList();
      notifyListeners();
    } catch (_) {/* ignore malformed relay */}
  }

  // -- iOS: mirror the in-process controller ---------------------------------

  void _syncFromController() {
    final c = StreamServerController.instance;
    _running = c.running;
    _pin = c.pin;
    _ip = c.ip;
    _port = c.port;
    _paired = c.pairedDesktops;
    notifyListeners();
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
