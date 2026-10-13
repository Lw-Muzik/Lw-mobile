/// Deciding when this phone should be reachable.
///
/// A held WebSocket keeps the phone's radio busier than most apps ever do, so
/// the phone is only on the hub when it is useful there. Two policies, chosen
/// by the platform:
///
/// # Android: on whenever Hype Connect is on
///
/// The user asked for exactly this: with Hype Connect switched on the phone
/// stays reachable from the background "without fail", with a persistent
/// notification saying what is happening. Android can honour it because a
/// foreground service (`ConnectService`) keeps the process alive and allowed to
/// hold a socket, so [backgroundAlways] is true there and the phone is on the
/// hub when
///
/// * Hype Connect is switched on, and
/// * the app is a music player — equalizer-only mode has no queue to drive.
///
/// Whether the screen is on, or music is playing, no longer matters.
///
/// # iOS (and anywhere without that service): only while useful
///
/// iOS suspends an idle app within seconds and has no foreground-service
/// equivalent, so holding a socket there would be a promise the platform
/// breaks. The phone is on the hub when, besides the two rules above, the app
/// is on screen **or** music is playing — a phone in a pocket playing a
/// playlist is exactly the one a laptop wants to control.
///
/// Leaving the screen with nothing playing does not drop the socket straight
/// away: people glance at another app and come back, and a reconnect is a token
/// check, a socket and a hello. The socket is let go [grace] after the app went
/// to the background silent; starting music or coming back before then keeps it.
///
/// On both platforms, switching Hype Connect off or leaving music-player mode
/// is immediate — those are decisions, not drift.
library;

import 'dart:async';

class ConnectPresence {
  ConnectPresence({
    required this._onWanted,
    this.grace = const Duration(minutes: 2),
    this.backgroundAlways = false,
  });

  /// Called with true when the phone should connect and false when it should
  /// disconnect — only when that actually changes.
  final void Function(bool wanted) _onWanted;

  final Duration grace;

  /// Stay on the hub in the background whatever is playing (Android, where a
  /// foreground service keeps the process alive). When false, the [grace] rule
  /// applies.
  final bool backgroundAlways;

  bool _enabled = false;
  bool _musicMode = true;
  bool _foreground = true;
  bool _playing = false;

  bool _connected = false;
  Timer? _graceTimer;

  /// Whether the phone is currently meant to be on the hub.
  bool get wanted => _connected;

  set enabled(bool value) => _set(() => _enabled = value);
  set musicMode(bool value) => _set(() => _musicMode = value);
  set foreground(bool value) => _set(() => _foreground = value);
  set playing(bool value) => _set(() => _playing = value);

  void _set(void Function() change) {
    change();
    _evaluate();
  }

  void _evaluate() {
    if (!_enabled || !_musicMode) {
      _transition(false);
      return;
    }
    if (backgroundAlways || _foreground || _playing) {
      _transition(true);
      return;
    }
    // Enabled, but on the background and silent. Stay as we are for [grace];
    // a phone that was not connected has nothing to let go of.
    if (_connected && _graceTimer == null) {
      _graceTimer = Timer(grace, () {
        _graceTimer = null;
        _transition(false);
      });
    }
  }

  void _transition(bool connect) {
    // Whatever was counting down is settled by this decision.
    _graceTimer?.cancel();
    _graceTimer = null;
    if (connect == _connected) return;
    _connected = connect;
    _onWanted(connect);
  }

  void dispose() {
    _graceTimer?.cancel();
    _graceTimer = null;
  }
}
