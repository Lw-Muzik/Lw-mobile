/// The tag that ties the mini player's cover to the full player's.
///
/// # Why one constant in its own file
///
/// A `Hero` pairs by tag across two routes, so the two ends have to agree
/// exactly. Both ends live far apart — one in the shell's bottom bar, one in the
/// player's card deck — and a tag typed out twice is a tag that will eventually
/// be typed differently, at which point the flight silently stops happening and
/// nothing fails.
///
/// A leaf file with no imports so either end can reach it without dragging the
/// other's dependencies along.
library;

/// Shared by the mini player's thumbnail and the playing card's artwork.
///
/// **Must appear at most once per route.** The card deck builds the tracks
/// either side of the current one as well, so only the card that is actually
/// playing may carry it — two heroes with one tag in a single route is an
/// assertion failure, not a degraded animation.
const String kNowPlayingHeroTag = 'now-playing-artwork';
