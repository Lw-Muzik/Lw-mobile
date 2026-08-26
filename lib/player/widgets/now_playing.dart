import 'package:flutter/material.dart';
import '/controllers/app_controller.dart';
import '/widgets/artwork_widget.dart';
import 'package:on_audio_query/on_audio_query.dart';

class NowPlaying extends StatefulWidget {
  final AppController controller;
  final ScrollController scrollController;

  const NowPlaying({
    super.key,
    required this.controller,
    required this.scrollController,
  });

  @override
  State<NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<NowPlaying> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentSong();
    });
  }

  void _scrollToCurrentSong() {
    if (!widget.scrollController.hasClients) return;
    final targetOffset = widget.controller.songId * 72.0;
    final maxScroll = widget.scrollController.position.maxScrollExtent;
    widget.scrollController.animateTo(
      targetOffset.clamp(0.0, maxScroll),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final songs = widget.controller.songs;
    final currentId = widget.controller.songId;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final theme = Theme.of(context);
    final surfaceColor = theme.scaffoldBackgroundColor;

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle bar + header (non-scrollable)
          const _SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                Text(
                  'QUEUE',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${songs.length} tracks',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _scrollToCurrentSong,
                  icon: Icon(
                    Icons.my_location_rounded,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    size: 20,
                  ),
                  tooltip: 'Jump to current',
                ),
              ],
            ),
          ),
          // Track list — uses the DraggableScrollableSheet's controller
          Expanded(
            child: ReorderableListView.builder(
              scrollController: widget.scrollController,
              padding: EdgeInsets.only(bottom: bottomPadding + 16),
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (oldIndex < newIndex) newIndex--;
                  songs.insert(newIndex, songs.removeAt(oldIndex));
                });
              },
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final t = Curves.easeInOut.transform(animation.value);
                    return Material(
                      color: Colors.transparent,
                      elevation: 8 * t,
                      shadowColor: Colors.black54,
                      child: child,
                    );
                  },
                  child: child,
                );
              },
              itemCount: songs.length,
              itemBuilder: (context, i) {
                return _QueueItem(
                  key: ValueKey('queue_$i'),
                  song: songs[i],
                  index: i,
                  isCurrent: i == currentId,
                  onTap: () {
                    widget.controller.playSongFromList(songs, i);
                  },
                  onDismissed: () {
                    setState(() {
                      songs.removeAt(i);
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Drag handle at the top of the sheet.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// Single queue item row.
class _QueueItem extends StatelessWidget {
  final SongModel song;
  final int index;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  const _QueueItem({
    super.key,
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.onTap,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;

    return Dismissible(
      key: ValueKey('dismiss_$index'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismissed(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.redAccent.withValues(alpha: 0.2),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.redAccent,
          size: 24,
        ),
      ),
      child: Material(
        color: isCurrent
            ? accentColor.withValues(alpha: 0.08)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                // Accent bar for active track
                Container(
                  width: 3,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isCurrent ? accentColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                // Track number or playing indicator
                SizedBox(
                  width: 28,
                  child: isCurrent
                      ? Icon(
                          Icons.bar_chart_rounded,
                          color: accentColor,
                          size: 20,
                        )
                      : Text(
                          '${index + 1}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.35,
                            ),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                // Artwork thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: ArtworkWidget(
                      width: 48,
                      height: 48,
                      size: 200,
                      quality: 50,
                      songId: song.id,
                      type: ArtworkType.AUDIO,
                      path: song.data,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Title + artist
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent
                              ? accentColor
                              : theme.colorScheme.onSurface,
                          fontSize: 15,
                          fontWeight: isCurrent
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artist ?? 'Unknown artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent
                              ? accentColor.withValues(alpha: 0.6)
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                // Drag handle
                Icon(
                  Icons.drag_handle_rounded,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
