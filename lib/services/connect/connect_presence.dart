/// Deciding when this phone should be reachable.
///
/// A held WebSocket keeps the phone's radio busier than most apps ever do, so
/// the phone is only on the hub when it is useful there:
///
/// * Hype Connect is switched on, and
/// * the app is a music player — equalizer-only mode has no queue to drive, and
/// * the app is on screen, **or** music is playing. A phone in a pocket playing
///   a playlist is exactly the one a laptop wants to control.
///
/// Leaving the screen with nothing playing does not drop the socket straight
/// away: people glance at another app and come back, and a reconnect is a token
/// check, a socket and a hello. The socket is let go [grace] after the app went
/// to the background silent; starting music or coming back before then keeps it.
/// Switching Hype Connect off, or leaving music-player mode, is immediate —
/// those are decisions, not drift.
library;

import 'dart:async';

class ConnectPresence {
  ConnectPresence({
    required this._onWanted,
    this.grace = const Duration(minutes: 2),
  });

  /// Called with true when the phone should connect and false when it should
  /// disconnect — only when that actually changes.
  final void Function(bool wanted) _onWanted;

  final Duration grace;

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
    if (_foreground || _playing) {
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
