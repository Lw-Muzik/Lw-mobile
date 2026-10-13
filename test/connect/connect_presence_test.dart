import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/services/connect/connect_presence.dart';

void main() {
  void scenario(void Function(FakeAsync async, ConnectPresence presence, List<bool> calls) body) {
    fakeAsync((async) {
      final calls = <bool>[];
      final presence = ConnectPresence(onWanted: calls.add);
      body(async, presence, calls);
      presence.dispose();
    });
  }

  test('does nothing while Hype Connect is off', () {
    scenario((async, p, calls) {
      p.foreground = true;
      p.playing = true;
      expect(calls, isEmpty);
      expect(p.wanted, isFalse);
    });
  });

  test('connects when enabled, a music player and on screen', () {
    scenario((async, p, calls) {
      p.enabled = true;
      expect(calls, [true]);
    });
  });

  test('does not connect in equalizer-only mode', () {
    scenario((async, p, calls) {
      p.musicMode = false;
      p.enabled = true;
      expect(calls, isEmpty);
    });
  });

  test('leaving music-player mode disconnects at once', () {
    scenario((async, p, calls) {
      p.enabled = true;
      p.musicMode = false;
      expect(calls, [true, false]);
    });
  });

  test('switching off disconnects at once, even while playing', () {
    scenario((async, p, calls) {
      p.enabled = true;
      p.playing = true;
      p.enabled = false;
      expect(calls, [true, false]);
    });
  });

  test('connects from the background when music starts', () {
    scenario((async, p, calls) {
      p.foreground = false;
      p.enabled = true;
      expect(calls, isEmpty);
      p.playing = true;
      expect(calls, [true]);
    });
  });

  test('stays connected for two minutes after backgrounding silent', () {
    scenario((async, p, calls) {
      p.enabled = true;
      p.foreground = false;
      async.elapse(const Duration(minutes: 1, seconds: 59));
      expect(calls, [true]);
      async.elapse(const Duration(seconds: 2));
      expect(calls, [true, false]);
    });
  });

  test('coming back within the grace keeps the connection', () {
    scenario((async, p, calls) {
      p.enabled = true;
      p.foreground = false;
      async.elapse(const Duration(minutes: 1));
      p.foreground = true;
      async.elapse(const Duration(minutes: 5));
      expect(calls, [true]);
    });
  });

  test('playing in the background is never let go', () {
    scenario((async, p, calls) {
      p.enabled = true;
      p.playing = true;
      p.foreground = false;
      async.elapse(const Duration(hours: 1));
      expect(calls, [true]);
    });
  });

  test('pausing in the background starts the grace from the pause', () {
    scenario((async, p, calls) {
      p.enabled = true;
      p.playing = true;
      p.foreground = false;
      async.elapse(const Duration(minutes: 30));
      p.playing = false;
      async.elapse(const Duration(minutes: 1));
      expect(calls, [true]);
      async.elapse(const Duration(minutes: 1, seconds: 1));
      expect(calls, [true, false]);
    });
  });

  test('music starting during the grace cancels the disconnect', () {
    scenario((async, p, calls) {
      p.enabled = true;
      p.foreground = false;
      async.elapse(const Duration(minutes: 1));
      p.playing = true;
      async.elapse(const Duration(minutes: 5));
      expect(calls, [true]);
    });
  });

  test('reconnects when the app returns after a disconnect', () {
    scenario((async, p, calls) {
      p.enabled = true;
      p.foreground = false;
      async.elapse(const Duration(minutes: 3));
      p.foreground = true;
      expect(calls, [true, false, true]);
    });
  });

  test('a phone that is not connected is not scheduled to disconnect', () {
    scenario((async, p, calls) {
      p.foreground = false;
      p.enabled = true;
      async.elapse(const Duration(minutes: 10));
      expect(calls, isEmpty);
    });
  });

  group('backgroundAlways (Android)', () {
    void android(void Function(FakeAsync async, ConnectPresence p, List<bool> calls) body) {
      fakeAsync((async) {
        final calls = <bool>[];
        final presence = ConnectPresence(onWanted: calls.add, backgroundAlways: true);
        body(async, presence, calls);
        presence.dispose();
      });
    }

    test('stays connected in the background, silent, for hours', () {
      android((async, p, calls) {
        p.enabled = true;
        p.foreground = false;
        async.elapse(const Duration(hours: 6));
        expect(calls, [true]);
        expect(p.wanted, isTrue);
      });
    });

    test('connects while backgrounded and silent', () {
      android((async, p, calls) {
        p.foreground = false;
        p.enabled = true;
        expect(calls, [true]);
      });
    });

    test('switching off still disconnects at once', () {
      android((async, p, calls) {
        p.enabled = true;
        p.foreground = false;
        p.enabled = false;
        expect(calls, [true, false]);
      });
    });

    test('equalizer-only mode still disconnects at once, and returning reconnects', () {
      android((async, p, calls) {
        p.enabled = true;
        p.foreground = false;
        p.musicMode = false;
        expect(calls, [true, false]);
        p.musicMode = true;
        expect(calls, [true, false, true]);
      });
    });

    test('does not connect in equalizer-only mode, in the background or not', () {
      android((async, p, calls) {
        p.musicMode = false;
        p.foreground = false;
        p.enabled = true;
        expect(calls, isEmpty);
      });
    });
  });
}
