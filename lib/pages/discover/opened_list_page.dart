/// One playlist or album, opened into its tracks.
///
/// Listing rather than playing is the point — see `yt_open.dart`. "Play all"
/// starts at the top and therefore queues the whole list; tapping a track starts
/// from that track, because a queue that grows behind the music can only extend
/// forwards without interrupting it.
library;

import 'package:flutter/material.dart';

import '../../services/ytmusic/parse/yt_tracks.dart';
import '../../services/ytmusic/yt_models.dart';
import '../../services/ytmusic/yt_playback.dart';
import '../../services/ytmusic/yt_repository.dart';
import 'widgets/yt_widgets.dart';
import 'yt_open.dart';

class YtOpenedListPage extends StatefulWidget {
  final ExploreItem item;

  const YtOpenedListPage({super.key, required this.item});

  @override
  State<YtOpenedListPage> createState() => _YtOpenedListPageState();
}

class _YtOpenedListPageState extends State<YtOpenedListPage> {
  YtTrackList? _list;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await YtMusicRepository.instance.openList(widget.item);
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
      });
      // Resolve the top of the list while the user is still reading it, so the
      // tap that follows costs nothing.
      YtMusicRepository.instance
          .prefetchAudio([for (final track in list.tracks) track.videoId]);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is YtException ? e.message : 'Could not open that.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final tracks = list?.tracks ?? const <YtTrack>[];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 260,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                list?.title ?? widget.item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
              background: _Header(
                item: widget.item,
                list: list,
                trackCount: tracks.length,
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: YtTrackSkeleton(),
            )
          else if (_error case final String message)
            SliverFillRemaining(
              hasScrollBody: false,
              child: YtMessage(
                icon: Icons.error_outline_rounded,
                title: "That didn't open",
                body: message,
                onRetry: _load,
              ),
            )
          else if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: YtMessage(
                icon: Icons.inbox_rounded,
                title: 'No tracks here',
                body: 'YouTube lists nothing playable in this one.',
                onRetry: _load,
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () => YtPlayback.play(context, tracks, 0),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('Play all'),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${tracks.length} '
                      '${tracks.length == 1 ? "track" : "tracks"}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5),
                          ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 90),
              sliver: SliverFixedExtentList(
                itemExtent: YtTrackRow.height,
                delegate: SliverChildBuilderDelegate(
                  childCount: tracks.length,
                  (context, index) => YtTrackRow(
                    track: tracks[index],
                    position: index + 1,
                    onTap: () => YtPlayback.play(context, tracks, index),
                    onMore: () => showTrackActions(context, tracks[index]),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final ExploreItem item;
  final YtTrackList? list;
  final int trackCount;

  const _Header({
    required this.item,
    required this.list,
    required this.trackCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artwork = list?.thumbnail ?? item.thumbnail;

    return Stack(
      fit: StackFit.expand,
      children: [
        // The art doubles as the backdrop, blurred behind its own scrim, so the
        // header needs no second image and no second download.
        if (artwork != null)
          Opacity(
            opacity: 0.35,
            child: YtArtwork(url: artwork, size: 400),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                theme.colorScheme.surface.withValues(alpha: 0.2),
                theme.colorScheme.surface,
              ],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 44, 20, 44),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                YtArtwork(url: artwork, size: 116),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.kind == ExploreKind.album ? 'ALBUM' : 'PLAYLIST',
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (list?.artist case final artist?)
                        Text(
                          artist,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        )
                      else if (item.subtitle case final subtitle?)
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
