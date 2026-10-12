import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:eq_app/services/connect/connect_account.dart';
import 'package:eq_app/services/connect/connect_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryStore implements ConnectSecretStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// A fake backend: records every request and answers from [handler].
class FakeBackend {
  FakeBackend(this.handler);

  final FutureOr<http.Response> Function(http.Request request) handler;
  final List<http.Request> requests = [];

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    return handler(request);
  });

  List<String> get paths => [for (final r in requests) '${r.method} ${r.url.path}'];
}

http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, Object?> tokenBody(String access, String refresh, {int expiresIn = 900}) => {
      'user': {'id': 'u-1'},
      'accessToken': access,
      'refreshToken': refresh,
      'expiresIn': expiresIn,
    };

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  final apiBase = Uri.parse('http://hub.test/api');
  const info = ConnectInstallInfo(os: 'android', appVersion: '1.0.21');

  ConnectAccount account(FakeBackend backend, MemoryStore store) => ConnectAccount(
        client: backend.client,
        apiBase: apiBase,
        store: store,
        installInfo: () async => info,
      );

  group('install id', () {
    test('is a v4 UUID, minted once and persisted', () async {
      final store = MemoryStore();
      final backend = FakeBackend((_) => json({}));
      final first = await account(backend, store).installId();
      expect(first, matches(_uuidV4));
      // A second process reading the same store sees the same id.
      final second = await account(backend, store).installId();
      expect(second, first);
      expect(store.values[ConnectAccount.installIdKey], first);
    });

    test('two concurrent first callers get one id', () async {
      final store = MemoryStore();
      var minted = 0;
      final a = ConnectAccount(
        client: FakeBackend((_) => json({})).client,
        apiBase: apiBase,
        store: store,
        installInfo: () async => info,
        newInstallId: () => 'id-${++minted}',
      );
      final ids = await Future.wait([a.installId(), a.installId()]);
      expect(ids, ['id-1', 'id-1']);
      expect(minted, 1);
    });
  });

  group('tokens', () {
    test('no tokens: bootstraps anonymously with exactly the allowed fields',
        () async {
      final store = MemoryStore();
      final backend = FakeBackend((_) => json(tokenBody('a1', 'r1')));
      final acc = account(backend, store);

      expect(await acc.accessToken(), 'a1');
      expect(backend.paths, ['POST /api/auth/anonymous']);
      final body = jsonDecode(backend.requests.single.body) as Map;
      // The backend validates with forbidNonWhitelisted: an extra key is a 400.
      expect(body.keys.toSet(), {'installId', 'os', 'appVersion'});
      expect(body['installId'], await acc.installId());
      expect(body['os'], 'android');
      expect(acc.userId, 'u-1');
      expect(store.values[ConnectAccount.tokensKey], isNotNull);
    });

    test('fresh tokens are used without a request', () async {
      final store = MemoryStore();
      final backend = FakeBackend((_) => json(tokenBody('a1', 'r1')));
      await account(backend, store).accessToken();
      backend.requests.clear();

      // A new process, same store.
      expect(await account(backend, store).accessToken(), 'a1');
      expect(backend.requests, isEmpty);
    });

    test('a token within a minute of expiry is refreshed first', () async {
      final store = MemoryStore();
      final start = DateTime(2026, 10, 12, 12);
      final backend = FakeBackend((request) {
        if (request.url.path.endsWith('/auth/anonymous')) {
          return json(tokenBody('a1', 'r1', expiresIn: 900));
        }
        expect(jsonDecode(request.body), {'refreshToken': 'r1'});
        return json(tokenBody('a2', 'r2'));
      });
      final acc = account(backend, store);
      await withClock(Clock.fixed(start), acc.accessToken);
      final token = await withClock(
        Clock.fixed(start.add(const Duration(seconds: 850))),
        acc.accessToken,
      );
      expect(token, 'a2');
      expect(backend.paths, ['POST /api/auth/anonymous', 'POST /api/auth/refresh']);
    });

    test('concurrent refreshes spend the refresh token once', () async {
      final store = MemoryStore();
      final gate = Completer<void>();
      final backend = FakeBackend((request) async {
        if (request.url.path.endsWith('/auth/anonymous')) {
          return json(tokenBody('a1', 'r1'));
        }
        await gate.future;
        return json(tokenBody('a2', 'r2'));
      });
      final acc = account(backend, store);
      await acc.accessToken();

      final all = Future.wait([acc.refresh(), acc.refresh(), acc.refresh()]);
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await all;

      expect(
        backend.paths.where((p) => p.endsWith('/auth/refresh')),
        hasLength(1),
      );
      expect(await acc.accessToken(), 'a2');
    });

    test('a refused refresh token falls back to an anonymous bootstrap',
        () async {
      final store = MemoryStore();
      var anon = 0;
      final backend = FakeBackend((request) {
        if (request.url.path.endsWith('/auth/anonymous')) {
          anon++;
          return json(tokenBody('a$anon', 'r$anon'));
        }
        return json({'message': 'Invalid or expired refresh token'}, 401);
      });
      final acc = account(backend, store);
      await acc.accessToken();
      await acc.refresh();

      expect(backend.paths, [
        'POST /api/auth/anonymous',
        'POST /api/auth/refresh',
        'POST /api/auth/anonymous',
      ]);
      expect(await acc.accessToken(), 'a2');
    });

    test('a refresh that fails for another reason keeps the tokens', () async {
      final store = MemoryStore();
      var failing = false;
      final backend = FakeBackend((request) {
        if (failing) throw http.ClientException('no route to host');
        return json(tokenBody('a1', 'r1'));
      });
      final acc = account(backend, store);
      await acc.accessToken();
      failing = true;

      await expectLater(acc.refresh(), throwsA(isA<http.ClientException>()));
      expect(
        backend.paths.where((p) => p.endsWith('/auth/anonymous')),
        hasLength(1),
        reason: 'no re-bootstrap on a network failure',
      );
      expect(store.values[ConnectAccount.tokensKey], contains('r1'));
    });

    test('resetSession drops the tokens and signs in again, same install',
        () async {
      final store = MemoryStore();
      var anon = 0;
      final backend = FakeBackend((request) {
        anon++;
        return json(tokenBody('a$anon', 'r$anon'));
      });
      final acc = account(backend, store);
      final id = await acc.installId();
      await acc.accessToken();
      await acc.resetSession();

      expect(backend.paths, ['POST /api/auth/anonymous', 'POST /api/auth/anonymous']);
      expect(jsonDecode(backend.requests.last.body)['installId'], id);
      expect(await acc.accessToken(), 'a2');
    });
  });

  group('ConnectApi', () {
    ConnectApi api(FakeBackend backend) => ConnectApi(
          client: backend.client,
          account: account(backend, MemoryStore()),
        );

    test('sends the Bearer token', () async {
      final backend = FakeBackend((request) {
        if (request.url.path.endsWith('/auth/anonymous')) {
          return json(tokenBody('a1', 'r1'));
        }
        expect(request.headers['authorization'], 'Bearer a1');
        return json({'devices': [], 'activeDeviceId': null});
      });
      final result = await api(backend).devices();
      expect(result.devices, isEmpty);
      expect(backend.paths.last, 'GET /api/connect/devices');
    });

    test('a 401 is answered by one refresh and one retry', () async {
      var devicesCalls = 0;
      final backend = FakeBackend((request) {
        final path = request.url.path;
        if (path.endsWith('/auth/anonymous')) return json(tokenBody('a1', 'r1'));
        if (path.endsWith('/auth/refresh')) return json(tokenBody('a2', 'r2'));
        devicesCalls++;
        if (request.headers['authorization'] == 'Bearer a1') {
          return json({'message': 'Unauthorized'}, 401);
        }
        return json({'devices': [], 'activeDeviceId': null});
      });
      await api(backend).devices();
      expect(devicesCalls, 2);
      expect(backend.paths, [
        'POST /api/auth/anonymous',
        'GET /api/connect/devices',
        'POST /api/auth/refresh',
        'GET /api/connect/devices',
      ]);
    });

    test('a second 401 is reported, not retried for ever', () async {
      final backend = FakeBackend((request) {
        final path = request.url.path;
        if (path.contains('/auth/')) return json(tokenBody('a', 'r'));
        return json({'message': 'Unauthorized'}, 401);
      });
      await expectLater(
        api(backend).devices(),
        throwsA(isA<ConnectHttpException>()
            .having((e) => e.statusCode, 'status', 401)),
      );
      expect(backend.paths.where((p) => p.contains('/connect/')), hasLength(2));
    });

    test('preview of an unknown code is a 404', () async {
      final backend = FakeBackend((request) {
        if (request.url.path.contains('/auth/')) return json(tokenBody('a', 'r'));
        return json({'message': 'Not Found', 'statusCode': 404}, 404);
      });
      await expectLater(
        api(backend).previewLink('483920'),
        throwsA(isA<ConnectHttpException>()
            .having((e) => e.statusCode, 'status', 404)),
      );
      expect(backend.paths.last, 'GET /api/connect/links/483920');
    });

    test('a 409 carries BOTH_HAVE_ACCOUNTS, top-level or nested', () async {
      for (final body in [
        {'code': 'BOTH_HAVE_ACCOUNTS'},
        {
          'message': {'code': 'BOTH_HAVE_ACCOUNTS'},
          'statusCode': 409,
        },
      ]) {
        final backend = FakeBackend((request) {
          if (request.url.path.contains('/auth/')) {
            return json(tokenBody('a', 'r'));
          }
          return json(body, 409);
        });
        await expectLater(
          api(backend).approveLink('483920'),
          throwsA(isA<ConnectHttpException>()
              .having((e) => e.code, 'code', 'BOTH_HAVE_ACCOUNTS')),
        );
        expect(backend.paths.last, 'POST /api/connect/links/483920/approve');
      }
    });

    test('revoke and deny hit their routes', () async {
      final backend = FakeBackend((request) {
        if (request.url.path.contains('/auth/')) return json(tokenBody('a', 'r'));
        return json({'ok': true});
      });
      final client = api(backend);
      await client.denyLink('111111');
      await client.revokeDevice('cm1web');
      expect(backend.paths.skip(1), [
        'POST /api/connect/links/111111/deny',
        'DELETE /api/connect/devices/cm1web',
      ]);
    });
  });
}
