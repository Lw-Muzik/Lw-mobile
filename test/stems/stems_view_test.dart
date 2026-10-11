/// The Stems tab on a phone: every stage fits a 360×640 screen inside the
/// Sound Effects page without scrolling or overflowing, and the pads, combos,
/// faders and Reset drive the mix the engine is given.
///
/// The page geometry is the real one — a 56 dp app bar with a 48 dp tab strip
/// under it, a 24 dp status bar and a 24 dp gesture bar — so "fits" here means
/// fits there.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eq_app/controllers/stems_controller.dart';
import 'package:eq_app/models/stems_engine_status.dart';
import 'package:eq_app/models/stems_mix.dart';
import 'package:eq_app/pages/stems_view.dart';
import 'package:eq_app/services/stems/stems_model_store.dart';
import 'package:eq_app/Themes/ember.dart';

import 'stems_fakes.dart';

final _theme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Ember.accent,
    brightness: Brightness.dark,
    surface: Ember.ground,
  ).copyWith(primary: Ember.accent, onPrimary: Ember.ground),
  scaffoldBackgroundColor: Ember.ground,
);

final _supported = {benchmarkKey: '{"ok":true,"rtf":0.3,"millis":1000}'};

void main() {
  late FakeStemsEngine native;
  late FakeStemsStore store;
  StemsController? controller;

  void stemsWidgetTest(
    String description,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(description, (tester) async {
      native = FakeStemsEngine()..install();
      // Haptics go to the platform channel; there is no platform here.
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (_) async => null,
      );
      try {
        await body(tester);
      } finally {
        // Let gesture timers (double-tap, long-press) run out first.
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpWidget(const SizedBox.shrink());
        controller?.dispose();
        controller = null;
        native.uninstall();
      }
    });
  }

  Future<StemsController> showStems(
    WidgetTester tester, {
    Size size = const Size(360, 640),
    bool modelReady = true,
    Map<String, Object> saved = const {},
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 72, bottom: 72);
    tester.view.viewPadding = const FakeViewPadding(top: 72, bottom: 72);
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(saved);
    final prefs = await SharedPreferences.getInstance();
    store = FakeStemsStore(ready: modelReady);
    final c = controller = StemsController(prefs: prefs, store: store)..start();
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            title: const Text('Sound Effects'),
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(kTextTabBarHeight),
              child: SizedBox(height: kTextTabBarHeight),
            ),
          ),
          body: SafeArea(child: StemsView(controller: c)),
        ),
      ),
    );
    c.setTabVisible(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return c;
  }

  Finder fader(Stem stem) => find.bySemanticsLabel('${stem.label} level');

  stemsWidgetTest('first use: the one-time download card, then its progress', (
    tester,
  ) async {
    final c = await showStems(tester, modelReady: false);

    expect(
      find.text('Stems need a one-time download (≈79 MB)'),
      findsOneWidget,
    );
    expect(find.text('Best on Wi-Fi'), findsOneWidget);
    expect(
      find.text('Stem separation: Spleeter by Deezer (MIT)'),
      findsOneWidget,
    );
    expect(find.text('Reset'), findsNothing);

    final release = Completer<void>();
    store.behaviour = (onProgress, onPhase, cancel) async {
      onPhase?.call(StemsDownloadPhase.downloading);
      onProgress?.call(const StemsDownloadProgress(39428280, 78856560));
      await Future.any([release.future, cancel!.whenCancelled]);
      throw const StemsDownloadCancelled();
    };
    await tester.tap(find.text('Download'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Downloading stems…'), findsOneWidget);
    expect(find.text('39.4 of 78.9 MB'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.stage, StemsStage.needsDownload);
    expect(find.text('Download'), findsOneWidget);
  });

  stemsWidgetTest('a failed download says why and offers Retry', (
    tester,
  ) async {
    final c = await showStems(tester, modelReady: false);
    store.behaviour = (_, _, _) async => throw const StemsDownloadException(
      'Check your connection and try again.',
    );
    await tester.tap(find.text('Download'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(c.stage, StemsStage.downloadFailed);
    expect(find.text("Download didn't finish"), findsOneWidget);
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  stemsWidgetTest('the speed test explains itself while it runs', (
    tester,
  ) async {
    final hold = Completer<bool>();
    native.loadGate = hold;
    await showStems(tester);

    expect(find.text("Checking this phone's speed…"), findsOneWidget);
    hold.complete(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('VOCALS'), findsOneWidget);
  });

  stemsWidgetTest('the mixer fits a 360×640 phone, greyed while preparing', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await showStems(tester, saved: _supported);

    expect(find.text('Preparing… 10%'), findsOneWidget);
    expect(
      find.text("Getting stems ready. You'll hear the original until then."),
      findsOneWidget,
    );
    for (final label in ['VOCALS', 'DRUMS', 'INSTRUMENTS']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('ON'), findsNWidgets(3));
    expect(find.text('100%'), findsNWidgets(3));
    for (final combo in StemCombo.values) {
      expect(find.text(combo.label), findsOneWidget);
    }
    expect(find.text('Reset'), findsOneWidget);
    final dimmed = tester
        .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
        .where((o) => o.opacity < 1);
    expect(dimmed, hasLength(2), reason: 'strips and combos, not the note');

    // Faders get real room even on a small phone.
    expect(tester.getSize(fader(Stem.vocals)).height, greaterThan(150));
    semantics.dispose();
  });

  stemsWidgetTest('pads, combos, faders and Reset drive the mix', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    native.status = {'state': 'ready', 'progress': 1.0};
    final c = await showStems(tester, saved: _supported);
    expect(find.text('Ready'), findsOneWidget);
    expect(
      tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .every((o) => o.opacity == 1),
      isTrue,
    );

    await tester.tap(find.text('VOCALS'));
    await tester.pump();
    expect(c.mix.padOn(Stem.vocals), isFalse);
    expect(find.text('OFF'), findsOneWidget);

    await tester.tap(find.text('VOCALS'));
    await tester.tap(find.text('Acapella'));
    await tester.pump();
    expect(c.mix.pads, [true, false, false]);
    await tester.tap(find.text('Acapella'));
    await tester.pump();
    expect(c.mix.pads, [true, true, true]);

    await tester.drag(fader(Stem.drums), const Offset(0, 90));
    await tester.pump();
    final dragged = c.mix.fader(Stem.drums);
    expect(dragged, lessThan(1.0));
    expect(c.engaged, isTrue);
    expect(find.text('${(dragged * 100).round()}%'), findsOneWidget);
    expect(native.lastArgs('stemsSetLevels')!['drums'], dragged);

    await tester.tap(fader(Stem.drums));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(fader(Stem.drums));
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.mix.fader(Stem.drums), 1.0, reason: 'double-tap is home');

    await tester.drag(fader(Stem.instruments), const Offset(0, 60));
    await tester.pump();
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(c.mix, StemsMix.initial);
    semantics.dispose();
  });

  stemsWidgetTest('a song stems cannot split says why, chip and note', (
    tester,
  ) async {
    native.status = {'state': 'unavailable', 'reason': 'protected'};
    await showStems(tester, saved: _supported);

    expect(find.text('This song is protected'), findsOneWidget);
    expect(
      find.text("This song is protected, so it can't be split."),
      findsOneWidget,
    );
  });

  stemsWidgetTest('a phone too slow is told so, calmly', (tester) async {
    await showStems(
      tester,
      saved: {benchmarkKey: '{"ok":true,"rtf":0.9,"millis":5000}'},
    );

    expect(
      find.text("This phone isn't fast enough for live stems"),
      findsOneWidget,
    );
    expect(find.text('Free up 79 MB'), findsOneWidget);
    expect(find.text('Test again'), findsOneWidget);
    expect(find.text('VOCALS'), findsNothing);
  });

  for (final size in const [Size(320, 568), Size(640, 360), Size(412, 915)]) {
    stemsWidgetTest('the mixer lays out without overflow at $size', (
      tester,
    ) async {
      await showStems(tester, size: size, saved: _supported);
      expect(find.text('INSTRUMENTS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  stemsWidgetTest('on a tablet each level stays on top of its fader', (
    tester,
  ) async {
    // A 10" tablet in portrait: the faders stop growing well short of the
    // column, and the readout must travel with them, not stay at the top.
    final semantics = tester.ensureSemantics();
    await showStems(tester, size: const Size(800, 1280), saved: _supported);
    expect(tester.takeException(), isNull);
    final readout = tester.getRect(find.text('100%').first);
    final fader = tester.getRect(find.bySemanticsLabel('Vocals level'));
    expect(fader.height, closeTo(440, 1));
    expect(readout.bottom, lessThanOrEqualTo(fader.top));
    expect(fader.top - readout.bottom, lessThan(12));
    semantics.dispose();
  });

  group('status wording', () {
    StemsEngineStatus unavailable(String reason) =>
        StemsEngineStatus(state: StemsEngineState.unavailable, reason: reason);

    test('the chip says what the spec says', () {
      expect(stemsChipLabel(StemsEngineStatus.starting), 'Preparing…');
      expect(
        stemsChipLabel(
          const StemsEngineStatus(
            state: StemsEngineState.preparing,
            progress: 0.42,
          ),
        ),
        'Preparing… 42%',
      );
      expect(
        stemsChipLabel(const StemsEngineStatus(state: StemsEngineState.ready)),
        'Ready',
      );
      expect(
        stemsChipLabel(unavailable('stream')),
        'Stems work on songs saved on your phone',
      );
      expect(stemsChipLabel(unavailable('fetch')), "Couldn't load this song");
      expect(
        stemsChipLabel(unavailable('protected')),
        'This song is protected',
      );
      for (final reason in ['unsupported', 'decode']) {
        expect(stemsChipLabel(unavailable(reason)), "Can't read this song");
      }
      expect(stemsChipLabel(StemsEngineStatus.idle), 'Play a song');
      expect(
        stemsChipLabel(const StemsEngineStatus(state: StemsEngineState.error)),
        "Couldn't split this song",
      );
    });

    test('every note says what is heard meanwhile', () {
      for (final status in [
        StemsEngineStatus.starting,
        StemsEngineStatus.idle,
        unavailable('stream'),
        unavailable('fetch'),
        unavailable('protected'),
        unavailable('decode'),
        unavailable('model'),
        unavailable('something-new'),
        const StemsEngineStatus(state: StemsEngineState.error),
      ]) {
        expect(stemsStatusNote(status), isNotEmpty, reason: '$status');
      }
    });
  });
}
