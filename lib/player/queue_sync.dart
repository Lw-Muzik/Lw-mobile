/// Keeping the gapless player's source list level with the app's queue.
///
/// The queue model ([AppController.songs]) is extended synchronously; the
/// player's own list is extended asynchronously, and a gapless *load* replaces
/// that list wholesale with a snapshot of the model taken when it started. An
/// append that lands while a load is in flight is therefore wiped out by it —
/// which is how a 25-track mix played as a single song.
///
/// So player-side appends wait for the load, run one at a time, and add
/// whatever the player is *missing* rather than assuming it holds everything
/// but the tracks just appended.
library;

class PlayerQueueSync {
  Future<void> _ops = Future.value();

  /// Runs [op] after every earlier one has finished, so two appends can never
  /// both decide the same tracks are missing.
  Future<void> serial(Future<void> Function() op) {
    final next = _ops.then((_) => op());
    _ops = next.catchError((Object _) {});
    return next;
  }

  /// Waits out [pendingLoad], then adds the model entries from the player's
  /// current length onward via [addFrom].
  ///
  /// Does nothing when the player holds nothing (its load failed — there is no
  /// queue to extend) or already holds everything.
  static Future<void> catchUp({
    required Future<void>? pendingLoad,
    required int Function() playerLength,
    required int Function() modelLength,
    required Future<void> Function(int from) addFrom,
  }) async {
    if (pendingLoad != null) {
      try {
        await pendingLoad;
      } catch (_) {}
    }
    final have = playerLength();
    if (have == 0 || have >= modelLength()) return;
    await addFrom(have);
  }
}
