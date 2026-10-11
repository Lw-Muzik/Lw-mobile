/// The live-stems platform contract, as Dart sends and reads it.
///
/// Android and iOS answer the same names with the same shapes, and the native
/// side is built separately from this one — so the argument names and types
/// are pinned here, and so is the rule that a missing engine, a platform
/// error or an answer of the wrong type reads as "no" rather than throwing
/// into the UI.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/Helpers/Channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const events = EventChannel('eq_app/stems_events');

  final calls = <MethodCall>[];
  late Object? Function(MethodCall call) answer;

  setUp(() {
    calls.clear();
    answer = (_) => null;
    messenger.setMockMethodCallHandler(Channel.channel, (call) async {
      calls.add(call);
      return answer(call);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(Channel.channel, null);
    messenger.setMockStreamHandler(events, null);
  });

  test('stemsLoadModel sends the directory and reads true as loaded', () async {
    answer = (_) => true;
    expect(await Channel.stemsLoadModel('/data/stems/v1'), isTrue);
    expect(calls.single.method, 'stemsLoadModel');
    expect(calls.single.arguments, {'dir': '/data/stems/v1'});
  });

  test('stemsLoadModel reads anything but true as not loaded', () async {
    for (final reply in <Object?>[false, null, 1, 'true', <String, Object>{}]) {
      answer = (_) => reply;
      expect(await Channel.stemsLoadModel('/x'), isFalse, reason: '$reply');
    }
  });

  test('stemsUnloadModel takes no arguments', () async {
    await Channel.stemsUnloadModel();
    expect(calls.single.method, 'stemsUnloadModel');
    expect(calls.single.arguments, isNull);
  });

  test('stemsBenchmark returns the native map', () async {
    answer = (_) => {'ok': true, 'rtf': 0.31, 'millis': 2400, 'error': null};
    final result = await Channel.stemsBenchmark();
    expect(calls.single.method, 'stemsBenchmark');
    expect(result, {'ok': true, 'rtf': 0.31, 'millis': 2400, 'error': null});
  });

  test('stemsBenchmark reads a non-map answer as no answer', () async {
    answer = (_) => 'fast';
    expect(await Channel.stemsBenchmark(), isNull);
  });

  test('stemsSetArmed sends the flag', () async {
    await Channel.stemsSetArmed(true);
    await Channel.stemsSetArmed(false);
    expect(calls.map((c) => c.method), ['stemsSetArmed', 'stemsSetArmed']);
    expect(calls.map((c) => c.arguments), [
      {'armed': true},
      {'armed': false},
    ]);
  });

  test('stemsSetLevels sends three doubles by name', () async {
    await Channel.stemsSetLevels(vocals: 0.0, drums: 0.5, instruments: 1.0);
    final call = calls.single;
    expect(call.method, 'stemsSetLevels');
    expect(call.arguments, {'vocals': 0.0, 'drums': 0.5, 'instruments': 1.0});
    for (final value in (call.arguments as Map).values) {
      expect(value, isA<double>(), reason: 'native reads doubles, not ints');
    }
  });

  test('stemsSetExcludedPrefixes sends the list', () async {
    await Channel.stemsSetExcludedPrefixes([
      '/tmp/hype_video/',
      '/storage/emulated/0/Music/HypeMuzik/A - B.m4a',
    ]);
    expect(calls.single.method, 'stemsSetExcludedPrefixes');
    expect(calls.single.arguments, {
      'prefixes': [
        '/tmp/hype_video/',
        '/storage/emulated/0/Music/HypeMuzik/A - B.m4a',
      ],
    });
  });

  test(
    'stemsGetStatus returns the native map, or null for anything else',
    () async {
      answer = (_) => {'state': 'ready', 'progress': 1.0};
      expect(await Channel.stemsGetStatus(), {
        'state': 'ready',
        'progress': 1.0,
      });
      answer = (_) => 42;
      expect(await Channel.stemsGetStatus(), isNull);
    },
  );

  group('without a native engine', () {
    setUp(() => messenger.setMockMethodCallHandler(Channel.channel, null));

    test('every call completes, and the answers read as no', () async {
      expect(await Channel.stemsLoadModel('/x'), isFalse);
      expect(await Channel.stemsBenchmark(), isNull);
      expect(await Channel.stemsGetStatus(), isNull);
      await Channel.stemsUnloadModel();
      await Channel.stemsSetArmed(true);
      await Channel.stemsSetLevels(vocals: 1, drums: 1, instruments: 1);
      await Channel.stemsSetExcludedPrefixes(const []);
    });
  });

  test('a platform error reads as no', () async {
    answer = (_) => throw PlatformException(code: 'STEMS', message: 'boom');
    expect(await Channel.stemsLoadModel('/x'), isFalse);
    expect(await Channel.stemsBenchmark(), isNull);
    await Channel.stemsSetArmed(true);
  });

  test('stemsEvents delivers each map event and skips anything else', () async {
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (arguments, sink) {
          sink.success({'state': 'preparing', 'progress': 0.25});
          sink.success('not a map');
          sink.success({'state': 'ready', 'trackKey': 'abc'});
        },
      ),
    );

    final received = await Channel.stemsEvents.take(2).toList();

    expect(received, [
      {'state': 'preparing', 'progress': 0.25},
      {'state': 'ready', 'trackKey': 'abc'},
    ]);
  });
}
