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

import 'package:flutter/material.dart';

/// Shared by the mini player's thumbnail and the playing card's artwork.
///
/// **Must appear at most once per route.** The card deck builds the tracks
/// either side of the current one as well, so only the card that is actually
/// playing may carry it — two heroes with one tag in a single route is an
/// assertion failure, not a degraded animation.
const String kNowPlayingHeroTag = 'now-playing-artwork';

/// The title, flying from the bar's 14px line to the player's 20px one.
const String kNowPlayingTitleHeroTag = 'now-playing-title';

/// The artist, likewise.
const String kNowPlayingArtistHeroTag = 'now-playing-artist';

/// A shuttle for the title and artist that fades out through the middle.
///
/// The words travel a long way and cross the cover on the way — the mini
/// player puts them beside a 42px thumbnail, the player puts them under a
/// 420px one. Flown at full opacity they slide straight over the artwork,
/// which is the single thing that made the transition look wrong.
///
/// Dipping to nothing at the halfway point keeps the movement — they lift off
/// and land in the right places — without the collision in between.
Widget fadeThroughShuttle(
  BuildContext context,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromContext,
  BuildContext toContext,
) {
  final opacity = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
  ]).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut));

  final destination = (toContext.widget as Hero).child;
  return FadeTransition(
    opacity: opacity,
    child: Material(type: MaterialType.transparency, child: destination),
  );
}

