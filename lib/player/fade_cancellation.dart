/// A crossfade's "stop what you are doing" flag, with a wake-up attached.
///
/// A crossfade spends most of its life waiting: for the next track to load off
/// the network, for its artwork, and then for twenty volume steps. Every one of
/// those waits is a moment the user may press next — and a cancel that is only
/// noticed when the wait finishes is indistinguishable, from the outside, from
/// a button that does nothing.
///
/// So cancelling both sets the flag *and* wakes whatever is waiting on it.
library;

import 'dart:async';

class FadeCancellation {
  var _cancelled = false;

  /// Completed by [cancel] to wake a pending [wait]. Recreated per wait so a
  /// long fade does not accumulate completers.
  Completer<void>? _wake;

  bool get isCancelled => _cancelled;

  /// Asks the fade to stop at its next opportunity, and wakes it now.
  void cancel() {
    _cancelled = true;
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  /// Waits [duration], or until [cancel] is called — whichever comes first.
  ///
  /// Returning early is the whole point: it is what turns "the fade notices in
  /// up to a second" into "the fade notices now".
  Future<void> wait(Duration duration) async {
    if (_cancelled) return;
    final wake = Completer<void>();
    _wake = wake;
    try {
      await Future.any([Future<void>.delayed(duration), wake.future]);
    } finally {
      _wake = null;
    }
  }
}
