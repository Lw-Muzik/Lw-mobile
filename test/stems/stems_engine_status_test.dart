/// Reading what the native engine says without trusting its types, and the
/// one rule that decides whether a phone gets live stems at all.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/models/stems_engine_status.dart';

void main() {
  group('StemsEngineStatus.fromMap', () {
    test('reads every field of a well-formed event', () {
      final status = StemsEngineStatus.fromMap({
        'state': 'unavailable',
        'reason': 'protected',
        'progress': 0.5,
        'aheadSeconds': 12.5,
        'trackKey': '/music/a.flac',
      });
      expect(status.state, StemsEngineState.unavailable);
      expect(status.reason, 'protected');
      expect(status.progress, 0.5);
      expect(status.aheadSeconds, 12.5);
      expect(status.trackKey, '/music/a.flac');
    });

    test('takes ints where doubles were meant, and clamps progress', () {
      final status = StemsEngineStatus.fromMap({
        'state': 'preparing',
        'progress': 3,
        'aheadSeconds': 4,
      });
      expect(status.progress, 1.0);
      expect(status.aheadSeconds, 4.0);
    });

    test('survives missing, mistyped and unknown fields', () {
      expect(StemsEngineStatus.fromMap(null), StemsEngineStatus.idle);
      final odd = StemsEngineStatus.fromMap({
        'state': 'warming-up',
        'reason': '',
        'progress': 'half',
        'aheadSeconds': -2,
        'trackKey': 7,
      });
      expect(odd.state, StemsEngineState.idle);
      expect(odd.reason, isNull);
      expect(odd.progress, 0);
      expect(odd.aheadSeconds, 0);
      expect(odd.trackKey, isNull);
    });

    test('every state the contract names is understood', () {
      for (final state in StemsEngineState.values) {
        expect(StemsEngineStatus.fromMap({'state': state.name}).state, state);
      }
    });
  });

  group('StemsBenchmark', () {
    StemsBenchmark result({bool ok = true, Object? rtf = 0.3}) =>
        StemsBenchmark.fromMap({'ok': ok, 'rtf': rtf, 'millis': 1500});

    test('supported up to and including a real-time factor of 0.6', () {
      expect(result(rtf: 0.6).supported, isTrue);
      expect(result(rtf: 0.6001).supported, isFalse);
      expect(result(rtf: 0.05).supported, isTrue);
    });

    test('ok: false is never supported, however fast', () {
      expect(result(ok: false, rtf: 0.1).supported, isFalse);
    });

    test('a broken measurement is a no', () {
      expect(result(rtf: null).supported, isFalse);
      expect(result(rtf: -1).supported, isFalse);
      expect(result(rtf: 'fast').supported, isFalse);
    });

    test('survives the round trip through preferences', () {
      for (final original in [
        result(rtf: 0.42),
        result(ok: false, rtf: 0.9),
        result(rtf: null),
      ]) {
        final restored = StemsBenchmark.fromMap(
          jsonDecode(jsonEncode(original.toJson())) as Map,
        );
        expect(restored, original);
        expect(restored.supported, original.supported);
      }
    });
  });
}
