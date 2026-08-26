/// Which client the resolver asks, and what it does when one refuses.
///
/// Measured live 2026-08-14, one IP, one minute, itag 140:
///
/// | client     | playability | `Range: bytes=0-` | past 1 MiB |
/// |------------|-------------|-------------------|------------|
/// | ANDROID_VR | OK          | 206               | 206        |
/// | IOS        | **OK**      | **403**           | **403**    |
///
/// An IOS answer therefore *looks* like a successful resolve and is a track
/// that plays nothing at all: the first thing any player sends is one
/// open-ended GET, and that is the request the url refuses. Everything below
/// exists so the resolver never hands one of those to the player.
///
/// Re-measured 2026-08-18, when every search result began skipping without a
/// note: ANDROID_VR had joined IOS on the wrong side of that table — but only
/// from client version **1.64** upward. See [androidVrVersions].
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/services/ytmusic/yt_innertube.dart';
import 'package:eq_app/services/ytmusic/yt_worker.dart';

/// A tube whose `player` call answers from a script instead of the network.
class _ScriptedTube extends YtInnerTube {
  _ScriptedTube(this.answers);

  /// One entry per expected call: the status to answer with, and the
  /// `visitorData` that answer carries — which the real [YtInnerTube] harvests
  /// out of `responseContext` on every response, refusals included.
  final List<({String status, String? carries})> answers;

  final calls = <String?>[];

  /// The identity each attempt presented, in order.
  final versions = <String?>[];

  @override
  Future<Map<String, dynamic>> playerOnce(
    String videoId,
    YtPlayerClient client, {
    String? version,
  }) async {
    // What this attempt presented, which is the whole question.
    calls.add(visitorData);
    versions.add(version);
    if (calls.length > answers.length) {
      throw StateError('asked ${calls.length} times, script has ${answers.length}');
    }
    final answer = answers[calls.length - 1];
    if (answer.carries != null) visitorData = answer.carries;
    return {
      'playabilityStatus': {'status': answer.status, 'reason': 'Sign in to confirm'},
    };
  }
}

/// `1.64.16` -> 164016, so versions can be compared as numbers.
int _ordinal(String version) {
  final parts = version.split('.').map(int.parse).toList();
  return parts[0] * 1000000 + parts[1] * 1000 + parts[2];
}

void main() {
  group('audio client order', () {
    test('never offers IOS — its urls refuse the request a player makes', () {
      expect(audioClientOrder, isNot(contains(YtPlayerClient.ios)));
    });

    /// The 2026-08-20 change. ANDROID_VR is now refused on *both* sides of the
    /// 1.64 wall — bot-checked below it, proof-of-origin gated at and above it
    /// — so it can no longer lead. VISIONOS is asked first because it is the
    /// one client measured that day still answering `OK` with a plaintext
    /// itag 140 that serves a whole file to one open-ended GET.
    test('asks VISIONOS first, the one client still serving whole files', () {
      expect(audioClientOrder.first, YtPlayerClient.visionOs);
    });

    test('keeps ANDROID_VR behind it as a second axis, not as the lead', () {
      expect(audioClientOrder, contains(YtPlayerClient.androidVr));
      expect(audioClientOrder.indexOf(YtPlayerClient.androidVr),
          greaterThan(audioClientOrder.indexOf(YtPlayerClient.visionOs)));
    });
  });

  /// The identity is the whole of what makes this client work, and every field
  /// here was measured on 2026-08-20 rather than guessed. A drifting
  /// `clientVersion` or a missing `deviceModel` reads to YouTube as a client it
  /// does not recognise, which is answered exactly like a bot.
  group('the VISIONOS identity presented', () {
    test('is the one measured serving an un-gated, plaintext itag 140', () {
      final identity = YtInnerTube.clientIdentity(YtPlayerClient.visionOs);

      expect(identity['clientName'], 'VISIONOS');
      expect(identity['clientVersion'], visionOsVersion);
      expect(identity['deviceMake'], 'Apple');
      expect(identity['deviceModel'], 'RealityDevice17,1');
      expect(identity['osName'], 'visionOS');
    });

    test('carries no androidSdkVersion — it is not an Android client', () {
      final identity = YtInnerTube.clientIdentity(YtPlayerClient.visionOs);
      expect(identity.containsKey('androidSdkVersion'), isFalse);
    });

    /// The UA is built from adjacent string literals, where a dropped trailing
    /// space silently welds two words together and leaves a UA YouTube cannot
    /// place — which is answered exactly like a bot. Pin the exact text.
    test('presents the exact user agent that was measured', () {
      expect(
        YtInnerTube.clientIdentity(YtPlayerClient.visionOs)['userAgent'],
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
        '(KHTML, like Gecko) Version/26.0 Safari/605.1.15',
      );
    });
  });

  group('VISIONOS is asked without a version rotation', () {
    test('a refusal costs two asks, not two per ANDROID_VR version', () async {
      final tube = _ScriptedTube([
        (status: 'LOGIN_REQUIRED', carries: 'fresh'),
        (status: 'LOGIN_REQUIRED', carries: null),
      ]);
      addTearDown(tube.close);

      final response =
          await tube.player('abc', client: YtPlayerClient.visionOs);

      expect(tube.calls, hasLength(2),
          reason: 'one identity, asked at most twice — there is no list of '
              'VISIONOS versions to walk');
      expect(response['playabilityStatus']['status'], 'LOGIN_REQUIRED');
    });

    test('presents no ANDROID_VR version at all', () async {
      final tube = _ScriptedTube([(status: 'OK', carries: 'v1')]);
      addTearDown(tube.close);

      await tube.player('abc', client: YtPlayerClient.visionOs);

      expect(tube.versions, [null]);
    });
  });

  group('a refusal is retried with a visitorData, not abandoned', () {
    test('an answer that is not a refusal is returned as it is', () async {
      final tube = _ScriptedTube([(status: 'OK', carries: 'v1')]);
      addTearDown(tube.close);

      await tube.player('abc');

      expect(tube.calls, hasLength(1), reason: 'nothing to retry');
    });

    test('cold: learns a visitorData from the refusal and asks again',
        () async {
      final tube = _ScriptedTube([
        (status: 'LOGIN_REQUIRED', carries: 'fresh'),
        (status: 'OK', carries: null),
      ]);
      addTearDown(tube.close);

      final response = await tube.player('abc');

      expect(tube.calls, [null, 'fresh'],
          reason: 'the refusal itself carries the token the retry needs');
      expect(response['playabilityStatus']['status'], 'OK');
    });

    /// The regression. Holding a visitorData used to *disable* the retry, on
    /// the reasoning that a token had already been tried — but a token that is
    /// no longer accepted is exactly the case that needs a new one. The whole
    /// session then fell through to IOS and played silence until the app was
    /// killed.
    test('stale: forgets the token it holds and asks cold, then retries',
        () async {
      final tube = _ScriptedTube([
        (status: 'LOGIN_REQUIRED', carries: 'stale'), // held token refused
        (status: 'LOGIN_REQUIRED', carries: 'fresh'), // asked cold
        (status: 'OK', carries: null), // asked with what that taught us
      ]);
      addTearDown(tube.close);
      tube.visitorData = 'stale';

      final response = await tube.player('abc');

      expect(tube.calls, ['stale', null, 'fresh'],
          reason: 'the second attempt must present nothing, or it repeats the '
              'request that was just refused');
      expect(response['playabilityStatus']['status'], 'OK');
    });

    test('gives up after the last identity rather than asking for ever',
        () async {
      // Two asks per version at most: one presenting what is held, one cold.
      final tube = _ScriptedTube(List.generate(
        androidVrVersions.length * 2,
        (i) => (status: 'LOGIN_REQUIRED', carries: 'tok$i'),
      ));
      addTearDown(tube.close);
      tube.visitorData = 'held';

      final response = await tube.player('abc');

      expect(tube.calls.length, lessThanOrEqualTo(androidVrVersions.length * 2),
          reason: 'bounded — a refused resolve must not become a request storm');
      expect(response['playabilityStatus']['status'], 'LOGIN_REQUIRED',
          reason: 'the caller sees the refusal and can say so');
    });
  });

  /// The 2026-08-18 bug, and the one thing that must never regress.
  ///
  /// From 1.64 upward YouTube hands ANDROID_VR a proof-of-origin gated url: it
  /// resolves `OK`, it serves a bounded slice, and it 403s the single
  /// open-ended GET every player opens with. Nothing before playback can tell
  /// one apart from a good url — which is exactly why it cost a day to find.
  group('the client versions presented', () {
    test('are all below 1.64, the version the gate starts at', () {
      for (final version in androidVrVersions) {
        expect(_ordinal(version), lessThan(_ordinal('1.64.0')),
            reason: '$version resolves OK and then plays nothing at all');
      }
    });

    test('there is more than one, because which is refused moves', () {
      expect(androidVrVersions.length, greaterThan(1));
    });
  });

  group('a refused identity is followed by the next one', () {
    test('the first identity that answers OK wins, and nothing more is asked',
        () async {
      final tube = _ScriptedTube([(status: 'OK', carries: 'v1')]);
      addTearDown(tube.close);

      await tube.player('abc');

      expect(tube.versions, [androidVrVersions.first]);
    });

    test('a refusal moves on to a different version, not the same one again',
        () async {
      final tube = _ScriptedTube([
        (status: 'LOGIN_REQUIRED', carries: 'a'), // v1, presenting nothing
        (status: 'LOGIN_REQUIRED', carries: 'a'), // v1 again with what it learned
        (status: 'OK', carries: null), // v2
      ]);
      addTearDown(tube.close);

      final response = await tube.player('abc');

      expect(response['playabilityStatus']['status'], 'OK');
      expect(tube.versions.last, androidVrVersions[1],
          reason: 'a different version is a different request; repeating the '
              'refused one is not');
    });
  });
}
