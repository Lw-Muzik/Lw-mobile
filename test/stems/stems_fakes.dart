/// Fakes shared by the stems tests: a model store with no disk or network,
/// and a native engine that records every call on the mocked `eq_app`
/// channel and can push events on `eq_app/stems_events`.
///
/// Install the engine inside the test body (see `stemsTest` in the controller
/// test): a mock event stream installed outside a `testWidgets` zone delivers
/// its events where `pump` never reaches.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/Helpers/Channel.dart';
import 'package:eq_app/services/stems/stems_model_store.dart';

const stemsEvents = EventChannel('eq_app/stems_events');
const benchmarkKey = 'stems.benchmark.spleeter-4stems-fp16.v1';
const fakeModelDir = '/fake/stems/spleeter-4stems-fp16-v1';

typedef FakeDownload = Future<void> Function(
  void Function(StemsDownloadProgress)? onProgress,
  void Function(StemsDownloadPhase)? onPhase,
  StemsCancelToken? cancel,
);

/// A model store with no disk or network behind it.
class FakeStemsStore extends StemsModelStore {
  FakeStemsStore({this.ready = false});

  bool ready;
  bool deleted = false;
  int downloads = 0;

  /// Replaces the default download, which succeeds at once.
  FakeDownload? behaviour;

  @override
  Future<bool> isReady() async => ready;

  @override
  Future<Directory> directory() async => Directory(fakeModelDir);

  @override
  Future<void> download({
    void Function(StemsDownloadProgress progress)? onProgress,
    void Function(StemsDownloadPhase phase)? onPhase,
    StemsCancelToken? cancel,
  }) async {
    downloads++;
    final custom = behaviour;
    if (custom != null) {
      await custom(onProgress, onPhase, cancel);
    } else {
      final total = manifest.totalBytes;
      onPhase?.call(StemsDownloadPhase.checking);
      onPhase?.call(StemsDownloadPhase.downloading);
      onProgress?.call(StemsDownloadProgress(total ~/ 2, total));
      onProgress?.call(StemsDownloadProgress(total, total));
    }
    ready = true;
  }

  @override
  Future<void> delete() async {
    ready = false;
    deleted = true;
  }
}

/// The native side: records every call and answers like a working engine.
class FakeStemsEngine {
  final calls = <MethodCall>[];
  bool loadOk = true;
  Map<String, Object?>? benchmark = {'ok': true, 'rtf': 0.3, 'millis': 1800};
  Map<String, Object?>? status = {'state': 'preparing', 'progress': 0.1};
  Completer<bool>? loadGate;
  MockStreamHandlerEventSink? sink;
  int listens = 0;

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(Channel.channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'stemsLoadModel':
          final gate = loadGate;
          return gate == null ? loadOk : await gate.future;
        case 'stemsBenchmark':
          return benchmark;
        case 'stemsGetStatus':
          return status;
      }
      return null;
    });
    messenger.setMockStreamHandler(
      stemsEvents,
      MockStreamHandler.inline(
        onListen: (_, events) {
          listens++;
          sink = events;
        },
        onCancel: (_) => sink = null,
      ),
    );
  }

  void uninstall() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(Channel.channel, null);
    messenger.setMockStreamHandler(stemsEvents, null);
  }

  List<String> get methods => [for (final c in calls) c.method];

  List<MethodCall> named(String method) => [
    for (final c in calls)
      if (c.method == method) c,
  ];

  Map<dynamic, dynamic>? lastArgs(String method) {
    final matching = named(method);
    return matching.isEmpty ? null : matching.last.arguments as Map;
  }
}
