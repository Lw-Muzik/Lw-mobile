import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/services/connect/connect_notification.dart';
import 'package:eq_app/services/connect/connect_service.dart';

class FakeBridge implements ConnectServiceBridge {
  bool running = false;
  bool startResult = true;
  final calls = <String>[];
  final updates = <ConnectNotificationContent>[];
  bool? bootEnabled;

  @override
  set onAction(void Function(String id)? handler) {}
  @override
  set onOpenRequested(void Function()? handler) {}
  @override
  set onVolumeChanged(void Function(double value)? handler) {}
  @override
  set onVolumeKey(void Function(String direction)? handler) {}
  @override
  Future<double?> getVolume() async => null;
  @override
  Future<bool> setVolume(double value) async => false;
  @override
  Future<void> watchVolume(bool on) async {}
  @override
  Future<void> setRemoteVolumeKeys(bool on) async {}

  @override
  Future<bool> isRunning() async => running;

  @override
  Future<bool> start() async {
    calls.add('start');
    if (startResult) running = true;
    return startResult;
  }

  @override
  Future<void> update(ConnectNotificationContent content) async {
    calls.add('update');
    updates.add(content);
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    running = false;
  }

  @override
  Future<void> setBootEnabled(bool enabled) async {
    calls.add('boot:$enabled');
    bootEnabled = enabled;
  }

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => true;
  @override
  Future<void> openBatterySettings() async {}
  @override
  Future<bool> takeOpenRequest() async => false;
}

void main() {
  late FakeBridge bridge;
  late String title;
  late ConnectServiceController controller;
  var permissionAsks = 0;

  void scenario(void Function(FakeAsync async) body) {
    fakeAsync((async) {
      bridge = FakeBridge();
      title = 'one';
      permissionAsks = 0;
      controller = ConnectServiceController(
        bridge: bridge,
        content: () => ConnectNotificationContent(title: title),
        requestNotifications: () async => permissionAsks++,
      );
      body(async);
      controller.dispose();
    });
  }

  Future<void> init(FakeAsync async, {bool wanted = true, bool foreground = true}) async {
    unawaited(controller.init(wanted: wanted, foreground: foreground));
    async.flushMicrotasks();
  }

  test('starts when wanted and on screen, then shows the notification', () {
    scenario((async) {
      init(async);
      expect(bridge.calls, ['boot:true', 'start', 'update']);
      expect(bridge.updates.single.title, 'one');
      expect(controller.running, isTrue);
    });
  });

  test('does not start from the background; starts on resume', () {
    scenario((async) {
      init(async, foreground: false);
      expect(bridge.calls, ['boot:true']);
      controller.setForeground(true);
      async.flushMicrotasks();
      expect(bridge.calls, ['boot:true', 'start', 'update']);
    });
  });

  test('a service already running (boot start) is adopted, not restarted', () {
    scenario((async) {
      bridge.running = true;
      init(async, foreground: false);
      expect(bridge.calls, ['boot:true', 'update']);
    });
  });

  test('a refused start is retried on the next resume', () {
    scenario((async) {
      bridge.startResult = false;
      init(async);
      expect(controller.running, isFalse);
      controller.setForeground(false);
      bridge.startResult = true;
      controller.setForeground(true);
      async.flushMicrotasks();
      expect(controller.running, isTrue);
    });
  });

  test('stops when no longer wanted, and mirrors the boot flag', () {
    scenario((async) {
      init(async);
      controller.setWanted(false);
      async.flushMicrotasks();
      expect(bridge.calls.takeLast(2), ['boot:false', 'stop']);
      expect(bridge.running, isFalse);
      expect(controller.running, isFalse);
    });
  });

  test('not wanted at start still clears a leftover service', () {
    scenario((async) {
      bridge.running = true;
      init(async, wanted: false);
      expect(bridge.calls, ['boot:false', 'stop']);
    });
  });

  test('a service that is not running is not stopped', () {
    scenario((async) {
      init(async, wanted: false);
      controller.setWanted(false);
      async.flushMicrotasks();
      expect(bridge.calls.where((c) => c == 'stop'), isEmpty);
    });
  });

  test('unchanged content is not pushed again', () {
    scenario((async) {
      init(async);
      controller.refresh();
      async.elapse(const Duration(seconds: 5));
      controller.refresh();
      expect(bridge.updates, hasLength(1));
    });
  });

  test('changes are pushed at most once a second, the latest wins', () {
    scenario((async) {
      init(async);
      title = 'two';
      controller.refresh();
      title = 'three';
      controller.refresh();
      title = 'four';
      controller.refresh();
      async.flushMicrotasks();
      expect(bridge.updates.map((u) => u.title), ['one']);
      async.elapse(const Duration(milliseconds: 1000));
      expect(bridge.updates.map((u) => u.title), ['one', 'four']);
    });
  });

  test('a change that reverts within the window sends nothing', () {
    scenario((async) {
      init(async);
      title = 'two';
      controller.refresh();
      title = 'one';
      controller.refresh();
      async.elapse(const Duration(seconds: 2));
      expect(bridge.updates, hasLength(1));
    });
  });

  test('a push waits out a stop: nothing is sent after it', () {
    scenario((async) {
      init(async);
      title = 'two';
      controller.refresh();
      controller.setWanted(false);
      async.elapse(const Duration(seconds: 3));
      expect(bridge.updates, hasLength(1));
    });
  });

  test('refresh before the service runs sends nothing', () {
    scenario((async) {
      init(async, foreground: false);
      controller.refresh();
      expect(bridge.updates, isEmpty);
    });
  });

  test('the user turning it on asks for the notification permission once', () {
    scenario((async) {
      unawaited(controller.userEnabled());
      async.flushMicrotasks();
      expect(permissionAsks, 1);
    });
  });
}

extension on List<String> {
  List<String> takeLast(int n) => sublist(length - n);
}
