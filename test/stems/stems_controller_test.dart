/// The Stems controller against a mocked `eq_app` channel: when the model is
/// loaded, when the one-time speed test runs and what is remembered of it,
/// when the engine is armed and disarmed, and how levels reach it.
///
/// Uses `testWidgets` for its fake clock — the level throttle and the idle
/// unload are both timers, and a test that waited for two real minutes would
/// never be run.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eq_app/controllers/stems_controller.dart';
import 'package:eq_app/models/stems_engine_status.dart';
import 'package:eq_app/models/stems_mix.dart';
import 'package:eq_app/services/stems/stems_model_store.dart';

import 'stems_fakes.dart';

String _verdict({required bool ok, required double rtf}) =>
    jsonEncode({'ok': ok, 'rtf': rtf, 'millis': 1000});

void main() {
  late FakeStemsEngine native;
  late SharedPreferences prefs;
  late FakeStemsStore store;
  StemsController? controller;

  Future<StemsController> start(
    WidgetTester tester, {
    bool modelReady = true,
    Map<String, Object> saved = const {},
    StemsStreamFetcher? fetchStream,
  }) async {
    SharedPreferences.setMockInitialValues(saved);
    prefs = await SharedPreferences.getInstance();
    store = FakeStemsStore(ready: modelReady);
    final c = controller = StemsController(
      prefs: prefs,
      store: store,
      fetchStream: fetchStream,
    );
    c.start();
    await tester.pump();
    return c;
  }

  /// Every test installs the fake engine inside its own fake-async zone — a
  /// mock stream installed in `setUp` would deliver its events in the real
  /// zone, where `pump` never reaches them — and disposes the controller
  /// before the binding checks for pending timers.
  void stemsTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      native = FakeStemsEngine()..install();
      try {
        await body(tester);
      } finally {
        controller?.dispose();
        controller = null;
        native.uninstall();
      }
    });
  }

  final supportedPhone = {benchmarkKey: _verdict(ok: true, rtf: 0.3)};

  group('opening the tab', () {
    stemsTest('loads a ready model and arms the engine with the current mix', (
      tester,
    ) async {
      final c = await start(tester, saved: supportedPhone);
      expect(c.stage, StemsStage.mixer);
      expect(native.calls, isEmpty, reason: 'nothing runs until it is wanted');

      c.setTabVisible(true);
      await tester.pump();

      expect(native.methods, [
        'stemsLoadModel',
        'stemsSetLevels',
        'stemsSetArmed',
        'stemsGetStatus',
      ]);
      expect(native.lastArgs('stemsLoadModel'), {'dir': fakeModelDir});
      expect(native.lastArgs('stemsSetLevels'), {
        'vocals': 1.0,
        'drums': 1.0,
        'instruments': 1.0,
      });
      expect(native.lastArgs('stemsSetArmed'), {'armed': true});
      expect(c.armed, isTrue);
      expect(c.nativeArmed, isTrue);
      expect(c.status.state, StemsEngineState.preparing);
      expect(c.status.progress, 0.1);
    });

    stemsTest('without a model it arms nothing and asks for the download', (
      tester,
    ) async {
      final c = await start(tester, modelReady: false);
      c.setTabVisible(true);
      await tester.pump();

      expect(c.stage, StemsStage.needsDownload);
      expect(c.armed, isTrue, reason: 'the tab is open');
      expect(c.nativeArmed, isFalse, reason: 'there is nothing to run');
      expect(native.calls, isEmpty);
    });

    stemsTest('reads as preparing until the engine first answers', (
      tester,
    ) async {
      final gate = native.loadGate = Completer<bool>();
      final c = await start(tester, saved: supportedPhone);
      c.setTabVisible(true);
      await tester.pump();
      expect(c.status, StemsEngineStatus.starting);

      gate.complete(true);
      await tester.pump();
      expect(c.status.progress, 0.1, reason: 'the engine has answered');
    });
  });

  group('the speed test', () {
    stemsTest('runs once after the first load and is remembered', (
      tester,
    ) async {
      final c = await start(tester);
      expect(c.stage, StemsStage.testingDevice);

      c.setTabVisible(true);
      await tester.pump();

      expect(native.methods.take(2), ['stemsLoadModel', 'stemsBenchmark']);
      expect(c.deviceSupport, StemsDeviceSupport.supported);
      expect(c.stage, StemsStage.mixer);
      expect(c.nativeArmed, isTrue);
      expect(jsonDecode(prefs.getString(benchmarkKey)!), {
        'ok': true,
        'rtf': 0.3,
        'millis': 1800,
      });

      // The next launch trusts the verdict instead of testing again.
      c.dispose();
      controller = null;
      native.calls.clear();
      final next = controller = StemsController(prefs: prefs, store: store)
        ..start();
      await tester.pump();
      next.setTabVisible(true);
      await tester.pump();
      expect(native.named('stemsBenchmark'), isEmpty);
      expect(next.stage, StemsStage.mixer);
    });

    stemsTest('waits for the tab if the user left while the model loaded', (
      tester,
    ) async {
      final gate = native.loadGate = Completer<bool>();
      final c = await start(tester);
      c.setTabVisible(true);
      await tester.pump();
      c.setTabVisible(false);
      gate.complete(true);
      await tester.pump();

      expect(native.named('stemsBenchmark'), isEmpty);
      expect(c.stage, StemsStage.testingDevice);

      native.loadGate = null;
      c.setTabVisible(true);
      await tester.pump();
      expect(native.named('stemsLoadModel'), hasLength(1));
      expect(native.named('stemsBenchmark'), hasLength(1));
      expect(c.stage, StemsStage.mixer);
    });

    stemsTest('a slow phone is told so, remembered, and its model unloaded', (
      tester,
    ) async {
      native.benchmark = {'ok': true, 'rtf': 0.8, 'millis': 4200};
      final c = await start(tester);
      c.setTabVisible(true);
      await tester.pump();

      expect(c.stage, StemsStage.unsupported);
      expect(c.benchmark?.rtf, 0.8);
      expect(native.methods, contains('stemsUnloadModel'));
      expect(native.named('stemsSetArmed'), isEmpty);
      expect(jsonDecode(prefs.getString(benchmarkKey)!)['rtf'], 0.8);
    });

    stemsTest('ok: false is a "no" as well', (tester) async {
      native.benchmark = {'ok': false, 'rtf': 0.2, 'millis': 10, 'error': 'x'};
      final c = await start(tester);
      c.setTabVisible(true);
      await tester.pump();
      expect(c.deviceSupport, StemsDeviceSupport.unsupported);
    });

    stemsTest('no answer is not a verdict: nothing is remembered', (
      tester,
    ) async {
      native.benchmark = null;
      final c = await start(tester);
      c.setTabVisible(true);
      await tester.pump();

      expect(c.stage, StemsStage.startFailed);
      expect(c.deviceSupport, StemsDeviceSupport.unknown);
      expect(prefs.containsKey(benchmarkKey), isFalse);

      native.benchmark = {'ok': true, 'rtf': 0.5, 'millis': 900};
      await c.retryEngine();
      await tester.pump();
      expect(c.stage, StemsStage.mixer);
    });

    stemsTest('"Test again" forgets the verdict and runs it again', (
      tester,
    ) async {
      final c = await start(
        tester,
        saved: {benchmarkKey: _verdict(ok: true, rtf: 0.9)},
      );
      expect(c.stage, StemsStage.unsupported);
      c.setTabVisible(true);
      await tester.pump();
      expect(native.calls, isEmpty, reason: 'a known "no" loads nothing');

      await c.retestDevice();
      await tester.pump();

      expect(native.methods.take(2), ['stemsLoadModel', 'stemsBenchmark']);
      expect(c.stage, StemsStage.mixer);
    });
  });

  stemsTest('a model the engine cannot load reads as a start failure', (
    tester,
  ) async {
    native.loadOk = false;
    final c = await start(tester, saved: supportedPhone);
    c.setTabVisible(true);
    await tester.pump();

    expect(c.stage, StemsStage.startFailed);
    expect(c.engineError, isNotNull);
    expect(native.named('stemsSetArmed'), isEmpty);
  });

  group('download', () {
    stemsTest('then load, speed test and arm, while the tab is open', (
      tester,
    ) async {
      final c = await start(tester, modelReady: false);
      c.setTabVisible(true);
      final stages = <StemsStage>[];
      c.addListener(() => stages.add(c.stage));

      await c.downloadModel();
      await tester.pump();

      expect(
        stages,
        containsAllInOrder([
          StemsStage.downloading,
          StemsStage.verifying,
          StemsStage.downloading,
          StemsStage.testingDevice,
          StemsStage.mixer,
        ]),
      );
      expect(c.downloadProgress, 1.0);
      expect(native.methods.take(2), ['stemsLoadModel', 'stemsBenchmark']);
      expect(c.nativeArmed, isTrue);
    });

    stemsTest('a failure shows why, and Retry starts again', (tester) async {
      final c = await start(tester, modelReady: false);
      store.behaviour = (_, _, _) async => throw const StemsDownloadException(
        'Check your connection and try again.',
      );

      await c.downloadModel();
      expect(c.stage, StemsStage.downloadFailed);
      expect(c.modelError, 'Check your connection and try again.');

      store.behaviour = null;
      await c.downloadModel();
      expect(c.stage, StemsStage.testingDevice);
      expect(store.downloads, 2);
    });

    stemsTest('cancel goes back to the download prompt', (tester) async {
      final c = await start(tester, modelReady: false);
      store.behaviour = (onProgress, _, cancel) async {
        onProgress?.call(const StemsDownloadProgress(1000, 78856560));
        await cancel!.whenCancelled;
        throw const StemsDownloadCancelled();
      };

      final download = c.downloadModel();
      await tester.pump();
      expect(c.stage, StemsStage.downloading);
      expect(c.downloadedBytes, 1000);

      c.cancelDownload();
      expect(c.cancellingDownload, isTrue);
      await download;

      expect(c.stage, StemsStage.needsDownload);
      expect(c.downloadedBytes, 0);
    });
  });

  group('arming', () {
    stemsTest('a changed mix keeps the engine armed after the tab closes', (
      tester,
    ) async {
      final c = await start(tester, saved: supportedPhone);
      final dots = <bool>[];
      c.engagedListenable.addListener(
        () => dots.add(c.engagedListenable.value),
      );
      c.setTabVisible(true);
      await tester.pump();

      c.setFader(Stem.vocals, 0.5);
      c.commitFader();
      c.setTabVisible(false);
      await tester.pump();

      expect(c.engaged, isTrue);
      expect(c.armed, isTrue);
      expect(native.named('stemsSetArmed').map((m) => m.arguments), [
        {'armed': true},
      ]);

      c.reset();
      await tester.pump();
      expect(c.engaged, isFalse);
      expect(native.lastArgs('stemsSetArmed'), {'armed': false});
      expect(dots, [true, false], reason: 'the "Stems on" dot follows');
    });

    stemsTest('with nothing changed, closing the tab disarms, and the model '
        'is unloaded after two idle minutes', (tester) async {
      final c = await start(tester, saved: supportedPhone);
      c.setTabVisible(true);
      await tester.pump();
      c.setTabVisible(false);
      await tester.pump();
      expect(native.lastArgs('stemsSetArmed'), {'armed': false});

      await tester.pump(const Duration(minutes: 1, seconds: 59));
      expect(native.named('stemsUnloadModel'), isEmpty);
      await tester.pump(const Duration(seconds: 2));
      expect(native.named('stemsUnloadModel'), hasLength(1));
      expect(c.modelLoaded, isFalse);

      native.calls.clear();
      c.setTabVisible(true);
      await tester.pump();
      expect(native.methods.first, 'stemsLoadModel');
      expect(c.nativeArmed, isTrue);
    });

    stemsTest('coming back within the two minutes keeps the model', (
      tester,
    ) async {
      final c = await start(tester, saved: supportedPhone);
      c.setTabVisible(true);
      await tester.pump();
      c.setTabVisible(false);
      await tester.pump(const Duration(minutes: 1));
      c.setTabVisible(true);
      await tester.pump(const Duration(minutes: 3));

      expect(native.named('stemsUnloadModel'), isEmpty);
      expect(native.named('stemsLoadModel'), hasLength(1));
    });
  });

  group('levels', () {
    stemsTest('are throttled during a drag, and the last one always arrives', (
      tester,
    ) async {
      final c = await start(tester, saved: supportedPhone);
      c.setTabVisible(true);
      await tester.pump();
      native.calls.clear();

      // 31 drag frames over ~155 ms.
      for (var i = 0; i <= 30; i++) {
        c.setFader(Stem.drums, 1.0 - i * 0.02);
        await tester.pump(const Duration(milliseconds: 5));
      }
      c.commitFader();
      await tester.pump(const Duration(milliseconds: 100));

      final sent = native.named('stemsSetLevels');
      expect(sent.length, lessThanOrEqualTo(8));
      expect(sent.length, greaterThanOrEqualTo(3));
      expect((sent.last.arguments as Map)['drums'], 0.4);
      expect(c.mix.fader(Stem.drums), 0.4);
    });

    stemsTest('pads and combos send effective levels at once', (tester) async {
      final c = await start(tester, saved: supportedPhone);
      c.setTabVisible(true);
      await tester.pump();

      c.setFader(Stem.vocals, 0.7);
      c.commitFader();
      c.togglePad(Stem.vocals);
      await tester.pump(Duration.zero);
      expect(native.lastArgs('stemsSetLevels'), {
        'vocals': 0.0,
        'drums': 1.0,
        'instruments': 1.0,
      });

      c.tapCombo(StemCombo.acapella);
      await tester.pump(Duration.zero);
      expect(native.lastArgs('stemsSetLevels'), {
        'vocals': 0.7,
        'drums': 0.0,
        'instruments': 0.0,
      });
      await tester.pump(const Duration(milliseconds: 50));
    });

    stemsTest('a change made before the engine is ready is sent anyway', (
      tester,
    ) async {
      final gate = native.loadGate = Completer<bool>();
      final c = await start(tester, saved: supportedPhone);
      c.setTabVisible(true);
      await tester.pump();

      c.togglePad(Stem.drums);
      await tester.pump(Duration.zero);
      expect(native.lastArgs('stemsSetLevels'), {
        'vocals': 1.0,
        'drums': 0.0,
        'instruments': 1.0,
      });
      expect(c.nativeArmed, isFalse);

      gate.complete(true);
      await tester.pump();
      expect(c.nativeArmed, isTrue);
      // Re-sent on arming, so the engine starts from the user's mix.
      final arm = native.methods.lastIndexOf('stemsSetArmed');
      final levels = native.methods.lastIndexOf('stemsSetLevels');
      expect(levels, lessThan(arm));
      expect(native.lastArgs('stemsSetLevels')!['drums'], 0.0);
      await tester.pump(const Duration(milliseconds: 50));
    });

    stemsTest('double-tap restores a fader, and re-enables its pad', (
      tester,
    ) async {
      final c = await start(tester, saved: supportedPhone);
      c.setFader(Stem.instruments, 0.2);
      c.togglePad(Stem.instruments);
      c.resetFader(Stem.instruments);
      expect(c.mix.fader(Stem.instruments), 1.0);
      expect(c.mix.padOn(Stem.instruments), isTrue);
      expect(c.engaged, isFalse);
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  group('engine events', () {
    stemsTest('drive the status the tab shows', (tester) async {
      final c = await start(tester, saved: supportedPhone);
      c.setTabVisible(true);
      await tester.pump();
      expect(native.listens, 1);

      native.sink!.success({
        'state': 'ready',
        'progress': 1.0,
        'trackKey': 'k',
      });
      await tester.pump();
      expect(c.status.isReady, isTrue);
      expect(c.status.trackKey, 'k');

      native.sink!.success({'state': 'unavailable', 'reason': 'protected'});
      await tester.pump();
      expect(c.status.state, StemsEngineState.unavailable);
      expect(c.status.reason, 'protected');
    });

    stemsTest('an event that beats the status snapshot wins', (tester) async {
      native.status = null; // the snapshot never arrives
      final c = await start(tester, saved: supportedPhone);
      c.setTabVisible(true);
      await tester.pump();
      expect(c.status, StemsEngineStatus.starting);

      native.sink!.success({'state': 'idle'});
      await tester.pump();
      expect(c.status.state, StemsEngineState.idle);
    });
  });

  group('streams', () {
    const url = 'https://rr1.googlevideo.com/videoplayback?id=7';
    Map<String, Object?> waiting([String key = url]) => {
      'state': 'unavailable',
      'reason': 'stream',
      'trackKey': key,
    };

    Future<StemsController> open(
      WidgetTester tester,
      FakeStreamFetcher fetcher,
    ) async {
      final c = await start(
        tester,
        saved: supportedPhone,
        fetchStream: fetcher.call,
      );
      c.setTabVisible(true);
      await tester.pump();
      return c;
    }

    stemsTest('a stream is fetched once, reads as preparing, then handed over', (
      tester,
    ) async {
      final fetcher = FakeStreamFetcher();
      final c = await open(tester, fetcher);

      native.sink!.success(waiting());
      await tester.pump();
      expect(fetcher.urls, [url]);
      expect(c.status.state, StemsEngineState.preparing);
      expect(c.status.progress, 0.0);

      fetcher.progress!(0.5);
      await tester.pump();
      expect(c.status.progress, closeTo(0.2, 1e-9), reason: 'download = 40%');

      native.sink!.success({...waiting(), 'progress': 0.0});
      await tester.pump();
      expect(fetcher.urls, [url], reason: 'one fetch per stream');

      fetcher.pending!.complete('/tmp/stems_streams/copy.m4a');
      await tester.pump();
      expect(native.lastArgs('stemsProvideStream'), {
        'url': url,
        'path': '/tmp/stems_streams/copy.m4a',
      });

      native.sink!.success({
        'state': 'preparing',
        'progress': 0.5,
        'trackKey': url,
      });
      await tester.pump();
      expect(c.status.progress, closeTo(0.7, 1e-9), reason: '40% + half of 60%');

      native.sink!.success({'state': 'ready', 'progress': 1.0, 'trackKey': url});
      await tester.pump();
      expect(c.status.isReady, isTrue);
    });

    stemsTest('a failed fetch says so', (tester) async {
      final fetcher = FakeStreamFetcher();
      final c = await open(tester, fetcher);
      native.sink!.success(waiting());
      await tester.pump();
      fetcher.pending!.completeError(const SocketException('offline'));
      await tester.pump();
      expect(c.status.state, StemsEngineState.unavailable);
      expect(c.status.reason, 'fetch');
      expect(native.named('stemsProvideStream'), isEmpty);
    });

    stemsTest('a stream this app cannot fetch stays a stream', (tester) async {
      final fetcher = FakeStreamFetcher();
      final c = await open(tester, fetcher);
      native.sink!.success(waiting('https://drive.example/file'));
      await tester.pump();
      fetcher.pending!.complete(null);
      await tester.pump();
      expect(c.status.state, StemsEngineState.unavailable);
      expect(c.status.reason, 'stream');
    });

    stemsTest('moving on to another song drops the fetch', (tester) async {
      final fetcher = FakeStreamFetcher();
      await open(tester, fetcher);
      native.sink!.success(waiting());
      await tester.pump();
      native.sink!.success({
        'state': 'ready',
        'progress': 1.0,
        'trackKey': '/music/a.mp3',
      });
      await tester.pump();
      expect(fetcher.tokens.single!.isCancelled, isTrue);
    });

    stemsTest('the queued stream is fetched once the playing one has its copy', (
      tester,
    ) async {
      const next = 'https://rr2.googlevideo.com/videoplayback?id=8';
      final fetcher = FakeStreamFetcher();
      await open(tester, fetcher);
      native.sink!.success({...waiting(), 'nextKey': next});
      await tester.pump();
      expect(fetcher.urls, [url], reason: 'the playing song first');

      fetcher.pending!.complete('/tmp/a.m4a');
      await tester.pump();
      expect(fetcher.urls, [url, next]);
      fetcher.pending!.complete('/tmp/b.m4a');
      await tester.pump();
      expect(native.named('stemsProvideStream').map((c) => c.arguments), [
        {'url': url, 'path': '/tmp/a.m4a'},
        {'url': next, 'path': '/tmp/b.m4a'},
      ]);

      // Its own turn: the copy is already there, nothing more to fetch.
      native.sink!.success({'state': 'preparing', 'trackKey': next});
      await tester.pump();
      expect(fetcher.urls, hasLength(2));
    });

    stemsTest('a song that needs a copy now takes over from the queued fetch', (
      tester,
    ) async {
      const next = 'https://rr2.googlevideo.com/videoplayback?id=8';
      const skipped = 'https://rr3.googlevideo.com/videoplayback?id=9';
      final fetcher = FakeStreamFetcher();
      await open(tester, fetcher);
      native.sink!.success({...waiting(), 'nextKey': next});
      await tester.pump();
      fetcher.pending!.complete('/tmp/a.m4a');
      await tester.pump();
      expect(fetcher.urls.last, next);

      // Still preparing the playing song: the queued fetch carries on.
      native.sink!.success({'state': 'preparing', 'trackKey': url, 'nextKey': next});
      await tester.pump();
      expect(fetcher.tokens.last!.isCancelled, isFalse);

      // The user jumps elsewhere in the queue.
      native.sink!.success(waiting(skipped));
      await tester.pump();
      expect(fetcher.tokens[1]!.isCancelled, isTrue);
      expect(fetcher.urls.last, skipped);
    });

    stemsTest('closing the tab with the original mix drops the fetch', (
      tester,
    ) async {
      final fetcher = FakeStreamFetcher();
      final c = await open(tester, fetcher);
      native.sink!.success(waiting());
      await tester.pump();
      c.setTabVisible(false);
      await tester.pump();
      expect(fetcher.tokens.single!.isCancelled, isTrue);
    });
  });

  stemsTest('"Free up" unloads, deletes the files and keeps the verdict', (
    tester,
  ) async {
    final c = await start(
      tester,
      saved: {benchmarkKey: _verdict(ok: false, rtf: 0.2)},
    );
    await c.deleteModel();

    expect(store.deleted, isTrue);
    expect(c.modelPhase, StemsModelPhase.absent);
    expect(c.stage, StemsStage.unsupported);
    expect(prefs.containsKey(benchmarkKey), isTrue);
  });

  stemsTest('the mix is not remembered: every start is the original', (
    tester,
  ) async {
    final c = await start(tester, saved: supportedPhone);
    c.tapCombo(StemCombo.karaoke);
    await tester.pump(const Duration(milliseconds: 50));
    c.dispose();
    controller = null;

    final next = controller = StemsController(prefs: prefs, store: store)
      ..start();
    await tester.pump();
    expect(next.mix, StemsMix.initial);
    expect(next.engaged, isFalse);
  });
}
