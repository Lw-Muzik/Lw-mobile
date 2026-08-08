/// What tapping something in Discover does.
///
/// Kept in one place because every screen shows the same five kinds of thing and
/// they must behave identically wherever they appear: a playlist opens the same
/// way from a genre shelf, a search result and an artist page.
///
/// The rule, taken from desktop: **opening a tile lists its tracks rather than
/// playing them.** Browsing is how you find out what something is, and a hundred
/// tracks starting unannounced on a single tap answers a question the user
/// hadn't asked yet. Rows — songs and videos — are the exception: they name one
/// thing to play, so they play.
library;

import 'package:flutter/material.dart';

import '../../Routes/routes.dart';
import '../../services/ytmusic/yt_download.dart';
import '../../services/ytmusic/yt_models.dart';
import '../../services/ytmusic/yt_playback.dart';
import 'artist_page.dart';
import 'opened_list_page.dart';

/// Opens [item], using [siblings] as the queue when it turns out to be a track.
///
/// [radio] asks for a station seeded from the tapped song instead of a queue of
/// its [siblings] — see [YtPlayback.play], which also decides what the Autoplay
/// preference has to say about it.
void openExploreItem(
  BuildContext context,
  ExploreItem item, {
  List<ExploreItem> siblings = const [],
  bool radio = false,
}) {
  switch (item.kind) {
    case ExploreKind.playlist:
    case ExploreKind.album:
      Routes.routeTo(YtOpenedListPage(item: item), context);
    case ExploreKind.artist:
      Routes.routeTo(YtArtistPage(item: item), context);
    case ExploreKind.video:
      // A video plays with the videos it was listed alongside, exactly as a
      // song plays with its siblings. Picking the third result in the Videos
      // tab used to give one video and then a station of audio.
      final videos = [
        for (final sibling in siblings)
          if (sibling.kind == ExploreKind.video) sibling.asTrack(),
      ];
      YtPlayback.watch(context, item.asTrack(), siblings: videos);
    case ExploreKind.song:
      // A song plays with whatever it was listed alongside, so tapping the
      // third song on a shelf continues into the fourth rather than stopping.
      final queue = [
        for (final sibling in siblings)
          if (sibling.kind == ExploreKind.song) sibling,
      ];
      final index = queue.indexWhere((s) => s.id == item.id);
      final tracks = queue.isEmpty
          ? [item.asTrack()]
          : [for (final song in queue) song.asTrack()];
      YtPlayback.play(context, tracks, index < 0 ? 0 : index, radio: radio);
  }
}

/// The actions on a track: watch it, download it.
///
/// Shown from the overflow on a row rather than on a long press, because a long
/// press inside a scrolling list is a gesture people trigger by accident.
Future<void> showTrackActions(BuildContext context, YtTrack track) async {
  final theme = Theme.of(context);
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Text(
              track.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.radio_rounded),
            title: const Text('Start radio'),
            subtitle: const Text('An endless station built from this song'),
            onTap: () {
              Navigator.pop(sheetContext);
              YtPlayback.startRadio(context, track);
            },
          ),
          if (track.hasVideo)
            ListTile(
              leading: const Icon(Icons.play_circle_outline_rounded),
              title: const Text('Watch video'),
              onTap: () {
                Navigator.pop(sheetContext);
                YtPlayback.watch(context, track);
              },
            ),
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: const Text('Download'),
            subtitle: const Text('Saves to your music library'),
            onTap: () {
              Navigator.pop(sheetContext);
              startDownload(context, track);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Downloads [track], reporting progress and the outcome in one snack bar.
///
/// Deliberately fire-and-forget from the caller's point of view: a download is
/// something you set going and keep browsing, not something you wait on.
void startDownload(BuildContext context, YtTrack track) {
  final messenger = ScaffoldMessenger.of(context);
  final progress = ValueNotifier<double?>(null);

  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(minutes: 10),
      behavior: SnackBarBehavior.floating,
      content: ValueListenableBuilder<double?>(
        valueListenable: progress,
        builder: (context, value, _) => Row(
          children: [
            SizedBox(
              width: 60,
              child: LinearProgressIndicator(
                value: value,
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Downloading ${track.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  YtDownloader.download(track, onProgress: (value) => progress.value = value)
      .then((result) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(switch (result) {
          YtDownloadSaved(inLibrary: true) => 'Saved to your music library',
          YtDownloadSaved(inLibrary: false) => 'Saved to this app',
          YtDownloadFailed(:final message) => message,
        }),
      ),
    );
    // Deliberately not disposed. Hiding a snack bar is animated, so its builder
    // is still listening well past this point, and disposing underneath it
    // throws. Nothing else holds the notifier once that widget is gone, so it
    // is collected on its own — which is the cheaper of the two mistakes.
  });
}
