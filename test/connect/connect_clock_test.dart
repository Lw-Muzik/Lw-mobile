import 'package:clock/clock.dart';
import 'package:eq_app/services/connect/connect_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('offset = serverTime - (sent + received) / 2', () {
    test('a symmetric exchange gives the exact offset', () {
      final c = HubClock();
      // Sent at 1000, back at 1100: the hub answered at the midpoint, 1050,
      // and its clock read 6050 then, so it is 5000 ahead.
      c.addSample(sentMs: 1000, receivedMs: 1100, serverTimeMs: 6050);
      expect(c.offsetMs, 5000);
      expect(c.roundTripMs, 100);
    });

    test('a hub behind us gives a negative offset', () {
      final c = HubClock();
      c.addSample(sentMs: 10000, receivedMs: 10020, serverTimeMs: 7010);
      expect(c.offsetMs, -3000);
    });

    test('an odd round trip rounds to the nearest millisecond', () {
      final c = HubClock();
      c.addSample(sentMs: 0, receivedMs: 3, serverTimeMs: 1000);
      // 1000 - 1.5 = 998.5
      expect(c.offsetMs, 999);
    });
  });

  group('the smallest round trip wins', () {
    test('a slow sample does not replace a fast one', () {
      final c = HubClock();
      c.addSample(sentMs: 0, receivedMs: 20, serverTimeMs: 1010); // off 1000, 20
      c.addSample(sentMs: 100, receivedMs: 700, serverTimeMs: 1900); // off 1450, 600
      expect(c.offsetMs, 1000);
      expect(c.roundTripMs, 20);
    });

    test('a faster later sample takes over', () {
      final c = HubClock();
      c.addSample(sentMs: 0, receivedMs: 300, serverTimeMs: 1150); // off 1000
      c.addSample(sentMs: 1000, receivedMs: 1010, serverTimeMs: 2105); // off 1100
      expect(c.offsetMs, 1100);
    });

    test('only the last [window] samples compete', () {
      final c = HubClock(window: 3);
      c.addSample(sentMs: 0, receivedMs: 2, serverTimeMs: 501); // off 500, rtt 2
      for (var i = 1; i <= 3; i++) {
        c.addSample(
          sentMs: i * 1000,
          receivedMs: i * 1000 + 50,
          serverTimeMs: i * 1000 + 25 + 900,
        ); // off 900, rtt 50
      }
      // The fast sample aged out.
      expect(c.offsetMs, 900);
    });

    test('an unusable sample is refused', () {
      final c = HubClock();
      expect(c.addSample(sentMs: 500, receivedMs: 400, serverTimeMs: 1), isFalse);
      expect(
        c.addSample(sentMs: 0, receivedMs: 20000, serverTimeMs: 1),
        isFalse,
      );
      expect(c.isMeasured, isFalse);
      expect(c.offsetMs, isNull);
    });
  });

  group('seed and now', () {
    test('welcome seeds an estimate that a real sample replaces', () {
      final c = HubClock();
      c.seedFromWelcome(serverTimeMs: 9000, receivedMs: 4000);
      expect(c.offsetMs, 5000);
      expect(c.isMeasured, isFalse);
      c.addSample(sentMs: 0, receivedMs: 10, serverTimeMs: 1005);
      expect(c.offsetMs, 1000);
    });

    test('nowMs adds the offset to the local clock', () {
      final c = HubClock();
      c.addSample(sentMs: 0, receivedMs: 10, serverTimeMs: 2005); // +2000
      withClock(Clock.fixed(DateTime.fromMillisecondsSinceEpoch(50000)), () {
        expect(c.nowMs(), 52000);
      });
    });

    test('with nothing known nowMs is the local clock', () {
      withClock(Clock.fixed(DateTime.fromMillisecondsSinceEpoch(50000)), () {
        expect(HubClock().nowMs(), 50000);
      });
    });
  });
}
