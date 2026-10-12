import 'package:eq_app/pages/hype_connect_page.dart';
import 'package:eq_app/services/connect/connect_account.dart';
import 'package:eq_app/services/connect/connect_client.dart';
import 'package:eq_app/services/connect/hype_connect.dart';
import 'package:flutter_test/flutter_test.dart';

String line({
  bool enabled = true,
  bool musicMode = true,
  bool wants = true,
  ConnectClientState connection = const ConnectClientState(ConnectStatus.online),
  String? notice,
}) =>
    connectStatusLine(
      enabled: enabled,
      musicMode: musicMode,
      wantsConnection: wants,
      connection: connection,
      notice: notice,
    );

void main() {
  group('connectStatusLine', () {
    test('off says how to turn it on', () {
      expect(line(enabled: false), startsWith('Off.'));
    });

    test('off after an unlink shows why instead', () {
      expect(line(enabled: false, notice: 'This phone was unlinked'),
          'This phone was unlinked');
    });

    test('equalizer-only mode explains itself, whatever the socket says', () {
      expect(line(musicMode: false), contains('equalizer-only'));
    });

    test('online is ready', () {
      expect(line(), startsWith('Ready.'));
    });

    test('retrying shows the wait and the reason', () {
      final text = line(
        connection: const ConnectClientState(
          ConnectStatus.retrying,
          retryIn: Duration(seconds: 8),
          lastError: 'Timed out',
        ),
      );
      expect(text, contains('in 8 s'));
      expect(text, contains('Timed out'));
    });

    test('resting in the background is not an error', () {
      expect(
        line(
          wants: false,
          connection: const ConnectClientState(ConnectStatus.off),
        ),
        startsWith('Resting.'),
      );
    });
  });

  group('describeLinkError', () {
    test('404 means expired or used', () {
      expect(describeLinkError(const ConnectHttpException(404, 'x')),
          contains('expired or was already used'));
    });

    test('409 BOTH_HAVE_ACCOUNTS names the two accounts', () {
      expect(
        describeLinkError(
          const ConnectHttpException(409, 'x', code: 'BOTH_HAVE_ACCOUNTS'),
        ),
        contains('different HypeMuzik accounts'),
      );
    });

    test('another 409 is a stale code, not an account clash', () {
      final text = describeLinkError(
        const ConnectHttpException(409, 'x', code: 'LINK_STALE'),
      );
      expect(text, isNot(contains('different HypeMuzik accounts')));
      expect(text, contains('new code'));
    });

    test('429 asks to wait', () {
      expect(describeLinkError(const ConnectHttpException(429, 'x')),
          contains('Wait a minute'));
    });

    test('anything else is generic', () {
      expect(describeLinkError(StateError('boom')), contains('Try again'));
    });
  });
}
