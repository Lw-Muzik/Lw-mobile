/// Choosing how good the picture should be.
///
/// The renditions come from the manifest itself, so the list is whatever
/// YouTube actually offered for this video rather than a fixed menu that
/// promises 4K for a clip that only exists at 480p.
///
/// **Auto is first and is the default**, because it is almost always the right
/// answer: adaptive selection is what keeps a video playing when the connection
/// dips, and pinning 1080p on a train replaces a brief drop in sharpness with a
/// stall. The pinned options exist for the two cases where a person genuinely
/// knows better than the algorithm — wanting maximum quality on a good
/// connection, and wanting minimum data on a metered one.
library;

import 'package:flutter/material.dart';
import 'package:just_audio/video.dart';

Future<void> showVideoQualitySheet(BuildContext context, VideoOutput video) {
  final theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => StreamBuilder<VideoState>(
      stream: video.stateStream,
      initialData: video.state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? const VideoState();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Row(
                  children: [
                    Text('Quality',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (state.hasVideo)
                      Text(
                        '${state.width}×${state.height} now',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                  ],
                ),
              ),
              _QualityTile(
                title: 'Auto',
                subtitle: 'Follows the connection',
                selected: !state.isPinned,
                onTap: () {
                  Navigator.pop(sheetContext);
                  video.selectQualityAt(-1);
                },
              ),
              // Bounded so a manifest with a dozen renditions cannot produce a
              // sheet taller than the screen.
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: state.renditions.length,
                  itemBuilder: (context, index) {
                    final rendition = state.renditions[index];
                    return _QualityTile(
                      title: rendition.label,
                      subtitle: _dataRate(rendition.bitrate),
                      selected: state.selectedIndex == index,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        video.selectQualityAt(index);
                      },
                    );
                  },
                ),
              ),
              if (state.renditions.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Text(
                    'This one is offered at a single quality.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ),
  );
}

/// A bitrate stated as the thing people actually care about — how fast their
/// data allowance goes.
String _dataRate(int bitsPerSecond) {
  if (bitsPerSecond <= 0) return '';
  final megabytesPerHour = bitsPerSecond * 3600 / 8 / 1000000;
  if (megabytesPerHour >= 1000) {
    return '${(megabytesPerHour / 1000).toStringAsFixed(1)} GB per hour';
  }
  return '${megabytesPerHour.round()} MB per hour';
}

class _QualityTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _QualityTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? theme.colorScheme.primary : null,
        ),
      ),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: selected
          ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }
}
