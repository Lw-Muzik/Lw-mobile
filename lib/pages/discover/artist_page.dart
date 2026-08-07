/// An artist's page: their top songs as rows, then their albums, singles and
/// videos as shelves.
///
/// "Play all" queues the rows only. The carousels are things to *open*, not
/// tracks, and flattening each of them would be dozens of requests for one play
/// button — which is the same call desktop makes, and what YouTube's own play
/// button does.
library;

import 'package:flutter/material.dart';

import '../../services/ytmusic/yt_models.dart';
import '../../services/ytmusic/yt_playback.dart';
import '../../services/ytmusic/yt_repository.dart';
import 'widgets/yt_widgets.dart';
import 'yt_open.dart';

class YtArtistPage extends StatefulWidget {
  final ExploreItem item;

  const YtArtistPage({super.key, required this.item});

  @override
  State<YtArtistPage> createState() => _YtArtistPageState();
}

class _YtArtistPageState extends State<YtArtistPage> {
  List<ExploreShelf> _shelves = const [];
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
      final shelves =
          await YtMusicRepository.instance.artistPage(widget.item.id);
      if (!mounted) return;
      setState(() {
        _shelves = shelves;
        _loading = false;
      });
      YtMusicRepository.instance.prefetchAudio([
        for (final shelf in shelves)
          for (final item in shelf.items)
            if (item.isPlayable) item.id,
      ]);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is YtException ? e.message : 'Could not load that artist.';
      });
    }
  }

  /// The playable rows across the page, credited to this artist where a row
  /// didn't link a credit — on their own page, an unlinked credit is them.
  List<YtTrack> get _tracks => [
        for (final shelf in _shelves)
          for (final item in shelf.items)
            if (item.isPlayable)
              item
                  .asTrack(
                    playlistId: widget.item.id,
                    playlistTitle: widget.item.title,
                  )
                  .copyWith(artist: item.artist ?? widget.item.title),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracks = _tracks;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 240,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.item.thumbnail != null)
                    Opacity(
                      opacity: 0.4,
                      child: YtArtwork(url: widget.item.thumbnail, size: 400),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          theme.colorScheme.surface.withValues(alpha: 0.1),
                          theme.colorScheme.surface,
                        ],
                      ),
                    ),
                  ),
                  Center(
                    child: YtArtwork(
                      url: widget.item.thumbnail,
                      size: 108,
                      circular: true,
                      placeholder: Icons.person_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: YtSkeleton(),
            )
          else if (_error case final String message)
            SliverFillRemaining(
              hasScrollBody: false,
              child: YtMessage(
                icon: Icons.error_outline_rounded,
                title: "That didn't load",
                body: message,
                onRetry: _load,
              ),
            )
          else if (_shelves.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: YtMessage(
                icon: Icons.inbox_rounded,
                title: 'Nothing listed',
                body: 'YouTube has no page for this artist right now.',
                onRetry: _load,
              ),
            )
          else ...[
            if (tracks.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: () => YtPlayback.play(context, tracks, 0),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('Play all'),
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
              sliver: SliverList.builder(
                itemCount: _shelves.length,
                itemBuilder: (context, index) => YtShelfRow(
                  shelf: _shelves[index],
                  onOpen: (item) => openExploreItem(
                    context,
                    item,
                    siblings: _shelves[index].items,
                  ),
                  onHold: (item) => showTrackActions(context, item.asTrack()),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
