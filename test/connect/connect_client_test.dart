import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:eq_app/services/connect/connect_client.dart';
import 'package:eq_app/services/connect/connect_protocol.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// A socket the test plays the hub for.
class FakeSocket implements ConnectSocket {
  FakeSocket(this.uri);

  final Uri uri;
  final Completer<void> _ready = Completer<void>();
  final StreamController<String> _incoming = StreamController<String>();
  final List<String> sent = [];

  @override
  int? closeCode;
  @override
  String? closeReason;
  int? clientCloseCode;

  @override
  Future<void> get ready => _ready.future;

  @override
  Stream<String> get messages => _incoming.stream;

  void open() {
    if (!_ready.isCompleted) _ready.complete();
  }

  void fail(Object error) {
    if (!_ready.isCompleted) _ready.completeError(error);
    if (!_incoming.isClosed) {
      _incoming.addError(error);
      _incoming.close();
    }
  }

  void receive(ConnectFrame frame) => _incoming.add(frame.encode());
  void receiveText(String text) => _incoming.add(text);

  void serverClose(int? code, [String? reason]) {
    closeCode = code;
    closeReason = reason;
    if (!_incoming.isClosed) _incoming.close();
  }

  @override
  void send(String text) => sent.add(text);

  @override
  Future<void> close([int? code, String? reason]) async {
    clientCloseCode = code;
    closeCode ??= code;
    if (!_incoming.isClosed) await _incoming.close();
  }

  List<Map<String, Object?>> get sentJson =>
      [for (final s in sent) jsonDecode(s) as Map<String, Object?>];
}

/// Always returns the same value, so the jitter factor is known.
class FixedRandom implements Random {
  FixedRandom(this.value);
  double value;
  @override
  double nextDouble() => value;
  @override
  bool nextBool() => false;
  @override
  int nextInt(int max) => 0;
}

const _device = DeviceHello(
  id: '6f1d2c3b-4a59-4e6f-8a7b-9c0d1e2f3a4b',
  kind: DeviceKind.mobile,
  name: "Bruno's Pixel",
  platform: 'android',
  appVersion: '1.0.21',
  caps: [ConnectCap.player, ConnectCap.yt, ConnectCap.local],
);

WelcomeFrame _welcome() => const WelcomeFrame(
      v: 1,
      deviceId: '6f1d2c3b-4a59-4e6f-8a7b-9c0d1e2f3a4b',
      serverTime: 1760295600000,
      devices: [],
      activeDeviceId: null,
      states: {},
    );

class Harness {
  Harness({this.autoOpen = true, double random = 0.5}) : rng = FixedRandom(random) {
    client = ConnectClient(
      wsUri: Uri.parse('ws://hub.test/api/connect/ws'),
      connect: (uri) {
        final socket = FakeSocket(uri);
        sockets.add(socket);
        if (autoOpen) socket.open();
        return socket;
      },
      accessToken: () async {
        if (tokenError != null) throw tokenError!;
        return 'token-$tokenVersion';
      },
      refreshToken: () async {
        refreshes++;
        tokenVersion++;
      },
      resetSession: () async => resets++,
      device: () async => _device,
      random: rng,
    );
    client.state.addListener(() => statuses.add(client.state.value.status));
    client.frames.listen(received.add);
  }

  final bool autoOpen;
  final FixedRandom rng;
  late final ConnectClient client;
  final sockets = <FakeSocket>[];
  final statuses = <ConnectStatus>[];
  final received = <ConnectFrame>[];
  int tokenVersion = 1;
  int refreshes = 0;
  int resets = 0;
  Object? tokenError;

  FakeSocket get last => sockets.last;
  ConnectStatus get status => client.state.value.status;
}

void main() {
  clockTests();
  group('connectBackoff', () {
    test('doubles from 1 s and caps at 30 s with no jitter at 0.5', () {
      final delays = [
        for (var i = 0; i < 8; i++) connectBackoff(i, 0.5).inMilliseconds,
      ];
      expect(delays, [1000, 2000, 4000, 8000, 16000, 30000, 30000, 30000]);
    });

    test('jitter stays within ±20 %', () {
      expect(connectBackoff(0, 0).inMilliseconds, 800);
      // nextDouble() is in [0, 1), so the top of the range is approached, not
      // reached.
      expect(connectBackoff(0, 0.9999).inMilliseconds, inInclusiveRange(1199, 1200));
      expect(connectBackoff(5, 0).inMilliseconds, 24000);
      expect(connectBackoff(5, 0.9999).inMilliseconds, inInclusiveRange(35990, 36000));
      // A very long outage must not overflow the shift.
      expect(connectBackoff(400, 0.5).inMilliseconds, 30000);
    });
  });

  group('session', () {
    test('opens one socket and says hello first, with the current token', () {
      fakeAsync((async) {
        final h = Harness();
        h.client.start();
        async.flushMicrotasks();

        expect(h.sockets, hasLength(1));
        expect(h.last.uri.toString(), 'ws://hub.test/api/connect/ws');
        expect(h.last.sentJson, hasLength(1));
        final hello = h.last.sentJson.first;
        expect(hello['t'], 'hello');
        expect(hello['v'], 1);
        expect(hello['token'], 'token-1');
        expect(hello['device'], _device.toJson());
        expect(h.status, ConnectStatus.connecting);
      });
    });

    test('welcome brings it online and is forwarded', () {
      fakeAsync((async) {
        final h = Harness();
        h.client.start();
        async.flushMicrotasks();
        expect(h.client.send(const AckFrame.ok('x')), isFalse,
            reason: 'nothing is sent before welcome');

        h.last.receive(_welcome());
        async.flushMicrotasks();
        expect(h.status, ConnectStatus.online);
        expect(h.received.single, isA<WelcomeFrame>());
        expect(h.client.send(const AckFrame.ok('x')), isTrue);
        expect(h.last.sentJson.last, {'t': 'ack', 'id': 'x', 'ok': true});
      });
    });

    test('frames before welcome are not forwarded', () {
      fakeAsync((async) {
        final h = Harness();
        h.client.start();
        async.flushMicrotasks();
        h.last.receive(const CmdFrame(id: 'c', from: 'w', cmd: PauseCommand()));
        async.flushMicrotasks();
        expect(h.received, isEmpty);
      });
    });

    test('no welcome within the timeout drops the socket and retries', () {
      fakeAsync((async) {
        final h = Harness();
        h.client.start();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 14));
        expect(h.sockets, hasLength(1));
        async.elapse(const Duration(seconds: 1));
        expect(h.sockets.first.clientCloseCode, 1000);
        expect(h.status, ConnectStatus.retrying);
        async.elapse(const Duration(seconds: 1));
        expect(h.sockets, hasLength(2));
      });
    });

    test('stop closes with 1000 and never reconnects', () {
      fakeAsync((async) {
        final h = Harness();
        h.client.start();
        async.flushMicrotasks();
        h.last.receive(_welcome());
        async.flushMicrotasks();

        unawaited(h.client.stop());
        async.flushMicrotasks();
        expect(h.last.clientCloseCode, 1000);
        expect(h.status, ConnectStatus.off);
        async.elapse(const Duration(minutes: 5));
        expect(h.sockets, hasLength(1));
      });
    });
  });

  group('backoff', () {
    test('a lost connection retries on the 1, 2, 4 … 30 s schedule', () {
      fakeAsync((async) {
        final h = Harness();
        h.client.start();
        async.flushMicrotasks();

        const expected = [1, 2, 4, 8, 16, 30, 30];
        for (final seconds in expected) {
          final before = h.sockets.length;
          h.last.serverClose(null);
          async.flushMicrotasks();
          expect(h.status, ConnectStatus.retrying);
          expect(h.client.state.value.retryIn, Duration(seconds: seconds));
          async.elapse(Duration(milliseconds: seconds * 1000 - 1));
          expect(h.sockets.length, before, reason: 'too early for ${seconds}s');
          async.elapse(const Duration(milliseconds: 1));
          expect(h.sockets.length, before + 1, reason: 'late for ${seconds}s');
        }
      });
    });

    test('a welcome resets the schedule', () {
      fakeAsync((async) {
        final h = Harness();
        h.client.start();
        async.flushMicrotasks();
        h.last.serverClose(null);
        async.elapse(const Duration(seconds: 1));
        h.last.serverClose(null);
        async.elapse(const Duration(seconds: 2));
        expect(h.client.attempt, 2);

        h.last.receive(_welcome());
        async.flushMicrotasks();
        expect(h.client.attempt, 0);

        h.last.serverClose(null);
        async.flushMicrotasks();
        expect(h.client.state.value.retryIn, const Duration(seconds: 1));
      });
    });

    test('jitter is applied from the injected random', () {
      fakeAsync((async) {
        final h = Harness(random: 0);
        h.client.start();
        async.flushMicrotasks();
        h.last.serverClose(null);
        async.flushMicrotasks();
        expect(h.client.state.value.retryIn, const Duration(milliseconds: 800));
      });
    });

    test('a socket that never opens counts as a failed attempt', () {
      fakeAsync((async) {
        final h = Harness(autoOpen: false);
        h.client.start();
        async.flushMicrotasks();
        h.last.fail(const SocketExceptionStub('refused'));
        async.flushMicrotasks();
        expect(h.status, ConnectStatus.retrying);
        expect(h.last.sent, isEmpty, reason: 'no hello on a dead socket');
        async.elapse(const Duration(seconds: 1));
        expect(h.sockets, hasLength(2));
      });
    });

    test('a token that cannot be had retries without opening a socket', () {
      fakeAsync((async) {
        final h = Harness();
        h.tokenError = Exception('offline');
        h.client.start();
        async.flushMicrotasks();
        expect(h.sockets, isEmpty);
        expect(h.status, ConnectStatus.retrying);
        h.tokenError = null;
        async.elapse(const Duration(seconds: 1));
        expect(h.sockets, hasLength(1));
      });
    });
  });

  group('close codes', () {
    void online(FakeAsync async, Harness h) {
      h.client.start();
      async.flushMicrotasks();
      h.last.receive(_welcome());
      async.flushMicrotasks();
    }

    for (final code in [ConnectCloseCodes.unauthorized, ConnectCloseCodes.merged]) {
      test('$code refreshes the token, then reconnects with the new one', () {
        fakeAsync((async) {
          final h = Harness();
          online(async, h);
          h.last.serverClose(code);
          async.flushMicrotasks();
          expect(h.refreshes, 1);
          expect(h.resets, 0);
          expect(h.status, ConnectStatus.retrying);
          async.elapse(const Duration(seconds: 1));
          expect(h.sockets, hasLength(2));
          expect(h.last.sentJson.first['token'], 'token-2');
        });
      });
    }

    test('4003 drops the session, says unlinked and stops', () {
      fakeAsync((async) {
        final h = Harness();
        online(async, h);
        h.last.serverClose(ConnectCloseCodes.revoked);
        async.flushMicrotasks();
        expect(h.status, ConnectStatus.unlinked);
        expect(h.client.state.value.lastError, 'This phone was unlinked');
        expect(h.resets, 1);
        async.elapse(const Duration(minutes: 10));
        expect(h.sockets, hasLength(1), reason: 'a revoked device stays revoked');
      });
    });

    test('4004 stops without touching the session', () {
      fakeAsync((async) {
        final h = Harness();
        online(async, h);
        h.last.serverClose(ConnectCloseCodes.replaced);
        async.flushMicrotasks();
        expect(h.status, ConnectStatus.replaced);
        expect(h.refreshes, 0);
        expect(h.resets, 0);
        async.elapse(const Duration(minutes: 10));
        expect(h.sockets, hasLength(1));
      });
    });

    for (final code in [4000, 4002, 1006, 1011]) {
      test('$code reconnects with backoff and no refresh', () {
        fakeAsync((async) {
          final h = Harness();
          online(async, h);
          h.last.serverClose(code);
          async.flushMicrotasks();
          expect(h.status, ConnectStatus.retrying);
          expect(h.refreshes, 0);
          async.elapse(const Duration(seconds: 1));
          expect(h.sockets, hasLength(2));
        });
      });
    }

    test('start after 4004 connects again (an explicit restart)', () {
      fakeAsync((async) {
        final h = Harness();
        online(async, h);
        h.last.serverClose(ConnectCloseCodes.replaced);
        async.flushMicrotasks();
        h.client.start();
        async.flushMicrotasks();
        expect(h.sockets, hasLength(2));
      });
    });
  });

  group('stale sockets', () {
    test('a replaced socket that opens late is not said hello on', () {
      fakeAsync((async) {
        final h = Harness(autoOpen: false);
        h.client.start();
        async.flushMicrotasks();
        final first = h.last;

        unawaited(h.client.stop());
        h.client.start();
        async.flushMicrotasks();
        final second = h.last;
        expect(second, isNot(same(first)));

        first.open();
        second.open();
        async.flushMicrotasks();
        expect(first.sent, isEmpty);
        expect(second.sentJson.single['t'], 'hello');
      });
    });
  });

  group('unreadable frames', () {
    test('a cmd that will not parse is acked failed under its own id', () {
      fakeAsync((async) {
        final h = Harness();
        h.client.start();
        async.flushMicrotasks();
        h.last.receive(_welcome());
        async.flushMicrotasks();

        h.last.receiveText(jsonEncode({
          't': 'cmd',
          'id': 'c-77',
          'from': 'w',
          'cmd': {'type': 'seek', 'positionMs': 'later'},
        }));
        h.last.receiveText(jsonEncode({
          't': 'rpc',
          'id': 'r-9',
          'from': 'w',
          'method': 'search',
        }));
        h.last.receiveText('not json at all');
        async.flushMicrotasks();

        // hello, then the clock ping that every welcome starts.
        expect(h.last.sentJson.skip(2), [
          {'t': 'ack', 'id': 'c-77', 'ok': false, 'error': 'failed'},
          {'t': 'rpc_result', 'id': 'r-9', 'ok': false, 'error': 'failed'},
        ]);
        expect(h.status, ConnectStatus.online);
      });
    });
  });
}

/// Stands in for a socket error without depending on `dart:io` details.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The hub clock (contract §3.7): a ping on every welcome and every 10 s.
void clockTests() {
  group('hub clock', () {
    test('pings on welcome, then every 10 s while online, and learns the offset',
        () {
      fakeAsync((async) {
        final h = Harness();
        h.client.start();
        async.flushMicrotasks();
        h.last.receive(_welcome());
        async.flushMicrotasks();

        List<Map<String, Object?>> pings() =>
            [for (final f in h.last.sentJson) if (f['t'] == 'ping') f];
        expect(pings(), hasLength(1));

        // The hub answers 40 ms later with its own clock: 5 s ahead of ours.
        async.elapse(const Duration(milliseconds: 40));
        final id = pings().single['id']! as String;
        final mid = clock.now().millisecondsSinceEpoch - 20;
        h.last.receive(PongFrame(id: id, serverTime: mid + 5000));
        async.flushMicrotasks();
        expect(h.client.hubClock.offsetMs, 5000);
        expect(h.client.hubClock.roundTripMs, 40);

        async.elapse(const Duration(seconds: 10));
        expect(pings(), hasLength(2));
        async.elapse(const Duration(seconds: 10));
        expect(pings(), hasLength(3));
      });
    });

    test('stops pinging when the socket goes away', () {
      fakeAsync((async) {
        final h = Harness();
        h.client.start();
        async.flushMicrotasks();
        h.last.receive(_welcome());
        async.flushMicrotasks();
        expect(async.periodicTimerCount, greaterThan(0), reason: 'pinging');
        final socket = h.last;
        socket.serverClose(1006);
        async.flushMicrotasks();
        final before = socket.sentJson.where((f) => f['t'] == 'ping').length;
        expect(async.periodicTimerCount, 0, reason: 'the ping timer is gone');
        async.elapse(const Duration(seconds: 25));
        expect(socket.sentJson.where((f) => f['t'] == 'ping').length, before);
      });
    });

    test('a pong nobody asked for changes nothing', () {
      fakeAsync((async) {
        final h = Harness();
        h.client.start();
        async.flushMicrotasks();
        h.last.receive(_welcome());
        async.flushMicrotasks();
        final before = h.client.hubClock.isMeasured;
        h.last.receive(const PongFrame(id: 'zzz', serverTime: 1));
        async.flushMicrotasks();
        expect(h.client.hubClock.isMeasured, before);
      });
    });
  });
}
