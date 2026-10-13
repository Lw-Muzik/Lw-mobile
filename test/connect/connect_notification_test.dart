import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/services/connect/connect_client.dart';
import 'package:eq_app/services/connect/connect_notification.dart';
import 'package:eq_app/services/connect/connect_protocol.dart';

const self = 'phone';

DeviceInfo device(
  String id, {
  String? name,
  bool online = true,
  DeviceKind kind = DeviceKind.desktop,
}) =>
    DeviceInfo(
      id: id,
      kind: kind,
      name: name ?? 'Device $id',
      platform: null,
      appVersion: null,
      caps: const [ConnectCap.player],
      online: online,
      lastSeenAt: '2026-01-01T00:00:00Z',
    );

TrackRef track({String title = 'Hey Jude', String? artist = 'The Beatles'}) =>
    YtTrackRef(videoId: 'v', title: title, artist: artist);

ConnectNotificationContent build({
  ConnectStatus status = ConnectStatus.online,
  Duration? retryIn,
  List<DeviceInfo> devices = const [],
  DeviceInfo? remote,
  TrackRef? remoteTrack,
  bool remotePlaying = false,
  bool hasLocal = false,
  String? localTitle,
  String? localArtist,
  bool localPlaying = false,
  String? controller,
}) =>
    buildConnectNotification(
      ConnectNotificationInput(
        status: status,
        retryIn: retryIn,
        thisDeviceId: self,
        devices: devices,
        remoteDevice: remote,
        remoteTrack: remoteTrack,
        remotePlaying: remotePlaying,
        hasLocalTrack: hasLocal,
        localTitle: localTitle,
        localArtist: localArtist,
        localPlaying: localPlaying,
        controllerId: controller,
      ),
    );

void main() {
  const turnOffOnly = [ConnectNotificationAction.turnOff];

  group('ready', () {
    test('connected with nothing playing anywhere', () {
      final c = build();
      expect(c.title, 'Ready for your devices');
      expect(c.text, isNotNull);
      expect(c.subText, isNull);
      expect(c.actions, turnOffOnly);
    });

    test('counts the other devices that are online, never this phone', () {
      final c = build(devices: [
        device(self, kind: DeviceKind.mobile),
        device('a'),
        device('b'),
        device('c', online: false),
      ]);
      expect(c.subText, '2 devices online');
    });

    test('one device is singular', () {
      expect(build(devices: [device(self), device('a')]).subText, '1 device online');
    });
  });

  group('playing on this phone', () {
    test('title, track line and no media buttons', () {
      final c = build(
        hasLocal: true,
        localPlaying: true,
        localTitle: 'Hey Jude',
        localArtist: 'The Beatles',
      );
      expect(c.title, 'Playing on this phone');
      expect(c.text, 'Hey Jude — The Beatles');
      expect(c.actions, turnOffOnly);
    });

    test('paused says so', () {
      final c = build(hasLocal: true, localTitle: 'Hey Jude', localArtist: 'x');
      expect(c.title, 'Paused on this phone');
    });

    test('missing artist leaves just the title', () {
      final c = build(hasLocal: true, localPlaying: true, localTitle: 'Hey Jude');
      expect(c.text, 'Hey Jude');
    });

    test('a placeholder artist is not shown', () {
      final c = build(
        hasLocal: true,
        localPlaying: true,
        localTitle: 'Hey Jude',
        localArtist: '<unknown>',
      );
      expect(c.text, 'Hey Jude');
    });

    test('missing everything still reads naturally', () {
      final c = build(hasLocal: true, localPlaying: true);
      expect(c.text, 'Unknown track');
    });

    test('shows who is controlling it, with the online count', () {
      final c = build(
        hasLocal: true,
        localPlaying: true,
        localTitle: 'Hey Jude',
        devices: [device(self), device('web', name: 'Chrome'), device('d')],
        controller: 'web',
      );
      expect(c.subText, 'Controlled from Chrome · 2 devices online');
    });

    test('a controller that went offline is not shown', () {
      final c = build(
        hasLocal: true,
        localPlaying: true,
        localTitle: 'Hey Jude',
        devices: [device(self), device('web', name: 'Chrome', online: false)],
        controller: 'web',
      );
      expect(c.subText, isNull);
    });

    test('a controller that is not in the list is not shown', () {
      final c = build(hasLocal: true, localTitle: 'x', controller: 'ghost');
      expect(c.subText, isNull);
    });

    test('this phone is never its own controller', () {
      final c = build(hasLocal: true, localTitle: 'x', controller: self, devices: [device(self)]);
      expect(c.subText, isNull);
    });
  });

  group('playing on another device', () {
    final laptop = device('laptop', name: 'Bruno’s MacBook');

    test('names the device and carries its transport buttons', () {
      final c = build(
        remote: laptop,
        remoteTrack: track(),
        remotePlaying: true,
        devices: [device(self), laptop],
      );
      expect(c.title, 'Playing on Bruno’s MacBook');
      expect(c.text, 'Hey Jude — The Beatles');
      expect(c.actions, [
        ConnectNotificationAction.previous,
        ConnectNotificationAction.pause,
        ConnectNotificationAction.next,
        ConnectNotificationAction.turnOff,
      ]);
      expect(c.subText, '1 device online');
    });

    test('paused offers play, not pause', () {
      final c = build(remote: laptop, remoteTrack: track());
      expect(c.title, 'Paused on Bruno’s MacBook');
      expect(c.actions[1], ConnectNotificationAction.play);
    });

    test('ignores whatever this phone itself holds', () {
      final c = build(
        remote: laptop,
        remoteTrack: track(title: 'Remote song'),
        remotePlaying: true,
        hasLocal: true,
        localPlaying: false,
        localTitle: 'Local song',
      );
      expect(c.text, startsWith('Remote song'));
    });

    test('has no "controlled from" line: this phone is the controller', () {
      final c = build(
        remote: laptop,
        remoteTrack: track(),
        remotePlaying: true,
        devices: [device(self), laptop, device('web')],
        controller: 'web',
      );
      expect(c.subText, '2 devices online');
    });

    test('remote that reports no track yet is still playing', () {
      final c = build(remote: laptop, remotePlaying: true);
      expect(c.title, startsWith('Playing on'));
      expect(c.text, isNull);
    });

    test('a silent remote with no track is just ready', () {
      final c = build(remote: laptop);
      expect(c.title, 'Ready for your devices');
      expect(c.actions, turnOffOnly);
    });

    test('a title without an artist', () {
      final c = build(
        remote: laptop,
        remoteTrack: track(artist: null),
        remotePlaying: true,
      );
      expect(c.text, 'Hey Jude');
    });

    test('an empty title falls back to the artist, then to unknown', () {
      expect(
        build(remote: laptop, remoteTrack: track(title: ' '), remotePlaying: true).text,
        'The Beatles',
      );
      expect(
        build(
          remote: laptop,
          remoteTrack: track(title: '', artist: null),
          remotePlaying: true,
        ).text,
        'Unknown track',
      );
    });
  });

  group('not connected', () {
    for (final status in [
      ConnectStatus.connecting,
      ConnectStatus.retrying,
      ConnectStatus.off,
    ]) {
      test('${status.name} reads as reconnecting, with only Turn off', () {
        final c = build(
          status: status,
          // Stale facts must not leak into a card that says we are offline.
          remote: device('laptop'),
          remoteTrack: track(),
          remotePlaying: true,
          hasLocal: true,
          localTitle: 'x',
          devices: [device('a')],
        );
        expect(c.title, 'Reconnecting…');
        expect(c.subText, isNull);
        expect(c.actions, turnOffOnly);
      });
    }

    test('retrying says when the next attempt is', () {
      final c = build(status: ConnectStatus.retrying, retryIn: const Duration(seconds: 8));
      expect(c.text, 'Cannot reach HypeMuzik, trying again in 8 s');
    });

    test('retrying without a wait', () {
      expect(build(status: ConnectStatus.retrying).text, 'Cannot reach HypeMuzik');
    });

    test('taken over by another connection', () {
      expect(
        build(status: ConnectStatus.replaced).title,
        'Taken over by another connection',
      );
    });

    test('unlinked', () {
      expect(build(status: ConnectStatus.unlinked).title, 'This phone was unlinked');
    });
  });

  group('content value', () {
    test('equal content is equal, so unchanged text is not re-sent', () {
      expect(build(), build());
      expect(build().hashCode, build().hashCode);
      expect(build(hasLocal: true, localTitle: 'a'), isNot(build(hasLocal: true, localTitle: 'b')));
    });

    test('actions serialise to ids native understands', () {
      final json = build(
        remote: device('l'),
        remoteTrack: track(),
        remotePlaying: true,
      ).toJson();
      expect(json['actions'], ['previous', 'pause', 'next', 'turnOff']);
      expect(ConnectNotificationAction.pause.id, 'toggle');
      expect(ConnectNotificationAction.play.id, 'toggle');
      expect(ConnectNotificationAction.turnOff.id, 'off');
    });
  });
}
