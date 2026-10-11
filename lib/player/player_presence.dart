/// Whether the full-screen player is somewhere on the navigation stack.
///
/// # Why it matters
///
/// The player's song actions open pages on top of it — an album, an artist —
/// and those pages play music. Playing has always opened the player, which
/// from there meant a second player stacked over the page over the first one,
/// and backing out walked through all of them. With the player already open,
/// "open the player" means go back to it.
///
/// Counted by the player itself as it is built and torn down, so every way
/// one is opened counts — the mini player's container transform as well as
/// `Routes.playerTo`.
///
/// Its own file, imported one way: `Routes` is imported under two spellings in
/// this app, which makes two copies of any state it holds.
library;

class PlayerPresence {
  const PlayerPresence._();

  static int _open = 0;

  /// The name every player route is pushed under.
  static const routeName = '/player';

  static bool get isOpen => _open > 0;

  static void opened() => _open++;

  static void closed() {
    if (_open > 0) _open--;
  }
}
